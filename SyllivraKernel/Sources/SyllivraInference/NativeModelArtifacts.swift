import Foundation
import CryptoKit
import CoreML
import SyllivraKernel

/// Integrity and tensor contracts for explicitly supplied native exports.
/// Validation does not certify model quality, provenance claims or license rights.
public struct NativeModelArtifacts: Sendable {
    public struct Manifest: Decodable, Sendable {
        public let schemaVersion: Int
        public let modelIdentifier: String
        public let upstreamRevision: String
        public let architecture: Architecture
        public let minimumIOSMajor: Int
        public let license: License
        public let files: [String: String]
        public let graphs: [Graph]
        public let contextWindowTokens: Int?
        public let vocabularySize: Int?
        public let tokenizer: Tokenizer?
    }

    public enum Architecture: String, Decodable, Sendable {
        case qwen25 = "qwen2_5", whisper, coreMLProbe = "coreml-probe"
    }

    public struct License: Decodable, Sendable {
        public let identifier: String
        public let source: String
    }

    public struct Tokenizer: Decodable, Sendable {
        public let path: String
        public let kind: String
        public let endTokenIDs: [Int]
    }

    public struct Graph: Decodable, Sendable {
        public let name: String
        public let path: String
        public let inputs: [Tensor]
        public let outputs: [Tensor]
        public let states: [Tensor]
    }

    public struct Tensor: Decodable, Sendable {
        public let name: String
        public let dataType: DataType
        public let shape: [Int]
        public let contextAxis: Int?
    }

    public enum DataType: String, Decodable, Sendable {
        case float16, float32, double, int32
        var byteWidth: Int { self == .float16 ? 2 : self == .double ? 8 : 4 }
        var coreML: MLMultiArrayDataType {
            switch self {
            case .float16: return .float16
            case .float32: return .float32
            case .double: return .double
            case .int32: return .int32
            }
        }
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case invalidManifest, wrongModel, wrongRevision, invalidPath, missingFile
        case hashMismatch, invalidTensor, invalidTokenizer, incompatibleModel, unknownGraph
        case unsupportedOS

        public var errorDescription: String? {
            switch self {
            case .invalidManifest: return "The native model manifest is missing or unsupported."
            case .wrongModel: return "The native artifacts belong to a different model."
            case .wrongRevision: return "The native artifacts have a different revision."
            case .invalidPath: return "The native artifacts contain an unsafe file path."
            case .missingFile: return "A required native model file is missing."
            case .hashMismatch: return "A native model file failed its integrity check."
            case .invalidTensor: return "The native model declares an invalid tensor or cache shape."
            case .invalidTokenizer: return "The native model tokenizer metadata is incomplete."
            case .incompatibleModel: return "The Core ML model does not match its tensor contract."
            case .unknownGraph: return "The requested native model graph is not declared."
            case .unsupportedOS: return "The native model requires a newer version of iOS."
            }
        }
    }

    public let directory: URL
    public let manifest: Manifest

    public init(directory: URL, expectedModelIdentifier: String? = nil, expectedRevision: String? = nil) throws {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        let url = self.directory.appendingPathComponent("native-runtime.json")
        guard let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              metadata.isRegularFile == true, metadata.isSymbolicLink != true,
              let size = metadata.fileSize, size > 0, size <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data) else {
            throw ValidationError.invalidManifest
        }
        manifest = decoded
        guard manifest.schemaVersion == 1, manifest.minimumIOSMajor >= 17,
              !manifest.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.upstreamRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.license.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.license.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.files.isEmpty, !manifest.graphs.isEmpty else { throw ValidationError.invalidManifest }
        if let expectedModelIdentifier, expectedModelIdentifier != manifest.modelIdentifier {
            throw ValidationError.wrongModel
        }
        if let expectedRevision, expectedRevision != manifest.upstreamRevision { throw ValidationError.wrongRevision }
        guard Set(manifest.graphs.map(\.name)).count == manifest.graphs.count else {
            throw ValidationError.invalidManifest
        }
        if let context = manifest.contextWindowTokens, context <= 0 { throw ValidationError.invalidTensor }
        if let size = manifest.vocabularySize, size <= 0 || size > Int(Int32.max) {
            throw ValidationError.invalidTokenizer
        }
        try verifyFiles()
        try verifyGraphContracts()
        if manifest.architecture != .coreMLProbe { try verifyTokenizer() }
    }

    private func verifyGraphContracts() throws {
        for graph in manifest.graphs {
            guard !graph.name.isEmpty, !graph.inputs.isEmpty, !graph.outputs.isEmpty,
                  ["mlmodel", "mlpackage", "mlmodelc"].contains(URL(fileURLWithPath: graph.path).pathExtension) else {
                throw ValidationError.invalidManifest
            }
            _ = try checkedURL(graph.path)
            for tensors in [graph.inputs, graph.outputs, graph.states] {
                guard Set(tensors.map(\.name)).count == tensors.count else { throw ValidationError.invalidTensor }
                for tensor in tensors {
                    guard !tensor.name.isEmpty, !tensor.shape.isEmpty else { throw ValidationError.invalidTensor }
                    var count = 1
                    for dimension in tensor.shape {
                        let product = count.multipliedReportingOverflow(by: dimension)
                        guard dimension > 0, !product.overflow else { throw ValidationError.invalidTensor }
                        count = product.partialValue
                    }
                    guard !count.multipliedReportingOverflow(by: tensor.dataType.byteWidth).overflow else {
                        throw ValidationError.invalidTensor
                    }
                    if let axis = tensor.contextAxis {
                        guard tensor.shape.indices.contains(axis), let context = manifest.contextWindowTokens,
                              context > 0, tensor.shape[axis] == context else { throw ValidationError.invalidTensor }
                    }
                }
            }
            guard graph.states.isEmpty || manifest.minimumIOSMajor >= 18 else { throw ValidationError.invalidTensor }
            try verifyGraphFiles(graph.path)
        }
    }

    private func verifyTokenizer() throws {
        guard let context = manifest.contextWindowTokens, context > 0,
              let size = manifest.vocabularySize, size > 0, size <= Int(Int32.max),
              let tokenizer = manifest.tokenizer,
              ["bpe", "whisper-bpe"].contains(tokenizer.kind),
              !tokenizer.endTokenIDs.isEmpty,
              Set(tokenizer.endTokenIDs).count == tokenizer.endTokenIDs.count,
              tokenizer.endTokenIDs.allSatisfy({ $0 >= 0 && $0 < size }),
              manifest.files[tokenizer.path] != nil else { throw ValidationError.invalidTokenizer }
        let tokenizerURL = try checkedURL(tokenizer.path)
        guard let fileSize = try tokenizerURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= 64 * 1024 * 1024,
              let json = try? JSONDecoder().decode(TokenizerDocument.self, from: Data(contentsOf: tokenizerURL)),
              json.model.type == "BPE", !json.model.vocab.isEmpty else { throw ValidationError.invalidTokenizer }
        var ids = Set(json.model.vocab.values)
        guard ids.count == json.model.vocab.count,
              ids.allSatisfy({ $0 >= 0 && $0 < size }) else { throw ValidationError.invalidTokenizer }
        for token in json.addedTokens ?? [] {
            guard !token.content.isEmpty, token.id >= 0, token.id < size,
                  !ids.contains(token.id) || json.model.vocab[token.content] == token.id else {
                throw ValidationError.invalidTokenizer
            }
            ids.insert(token.id)
        }
        guard tokenizer.endTokenIDs.allSatisfy(ids.contains) else { throw ValidationError.invalidTokenizer }
        for output in manifest.graphs.flatMap(\.outputs) where output.name == "logits" {
            guard output.shape.last == size else { throw ValidationError.invalidTensor }
        }
    }

    private struct TokenizerDocument: Decodable {
        struct Model: Decodable { let type: String; let vocab: [String: Int] }
        struct AddedToken: Decodable { let id: Int; let content: String }
        let model: Model
        let addedTokens: [AddedToken]?
        enum CodingKeys: String, CodingKey { case model; case addedTokens = "added_tokens" }
    }

    /// Compiles source graphs when necessary and checks actual SDK tensor descriptions.
    /// The caller owns residency and inference; extensions must not call this method.
    public func loadModel(named name: String, computeUnits: MLComputeUnits = .cpuOnly) async throws -> MLModel {
        try Task.checkCancellation()
        #if os(iOS)
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= manifest.minimumIOSMajor else {
            throw ValidationError.unsupportedOS
        }
        #endif
        guard let graph = manifest.graphs.first(where: { $0.name == name }) else { throw ValidationError.unknownGraph }
        // Recheck on load: a file may have changed since the manifest was inspected.
        try verifyFiles()
        try verifyGraphFiles(graph.path)
        let source = try checkedURL(graph.path)
        let modelURL = source.pathExtension == "mlmodelc" ? source : try await MLModel.compileModel(at: source)
        try Task.checkCancellation()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        try Task.checkCancellation()
        try verifyTensors(graph.inputs, descriptions: model.modelDescription.inputDescriptionsByName)
        try verifyTensors(graph.outputs, descriptions: model.modelDescription.outputDescriptionsByName)
        if #available(iOS 18.0, macOS 15.0, *) {
            let descriptions = model.modelDescription.stateDescriptionsByName
            guard Set(descriptions.keys) == Set(graph.states.map(\.name)) else { throw ValidationError.incompatibleModel }
            for tensor in graph.states {
                guard let constraint = descriptions[tensor.name]?.stateConstraint,
                      constraint.dataType == tensor.dataType.coreML,
                      constraint.bufferShape == tensor.shape else { throw ValidationError.incompatibleModel }
            }
        } else if !graph.states.isEmpty { throw ValidationError.unsupportedOS }
        return model
    }

    /// Greedy decoding for the owned single-token Qwen export. Pass a model from
    /// `loadModel`; the existing caller owns residency, serialization and foreground policy.
    @available(iOS 18.0, macOS 15.0, *)
    public func generate(using model: MLModel, inputTokens: [Int32], maximumNewTokens: Int,
                         endTokenIDs: Set<Int32>, deadline: PolishDeadline = PolishDeadline()) async throws -> [Int32] {
        try Task.checkCancellation()
        guard deadline.instant > .now else { throw PolishExecutionError.timedOut }
        guard let context = manifest.contextWindowTokens, let vocabulary = manifest.vocabularySize,
              let graph = manifest.graphs.first(where: { $0.name == "decoder" }), !graph.states.isEmpty,
              manifest.architecture == .qwen25 || manifest.architecture == .coreMLProbe,
              graph.inputs.count == 3, graph.outputs.count == 1,
              graph.inputs.contains(where: { $0.name == "input_ids" && $0.shape == [1, 1] && $0.dataType == .int32 }),
              graph.inputs.contains(where: { $0.name == "position" && $0.shape == [1] && $0.dataType == .int32 }),
              graph.inputs.contains(where: { $0.name == "causal_mask" && $0.shape == [1, 1, 1, context] && $0.dataType == .float32 }),
              graph.outputs.contains(where: { $0.name == "logits" && $0.shape == [1, vocabulary] && $0.dataType == .float32 }) else {
            throw ValidationError.incompatibleModel
        }
        guard !inputTokens.isEmpty, !endTokenIDs.isEmpty,
              inputTokens.allSatisfy({ $0 >= 0 && Int($0) < vocabulary }),
              endTokenIDs.allSatisfy({ $0 >= 0 && Int($0) < vocabulary }) else {
            throw ValidationError.invalidTokenizer
        }
        guard maximumNewTokens > 0, maximumNewTokens <= 2048,
              maximumNewTokens <= context, inputTokens.count <= context - maximumNewTokens,
              context <= Int(Int32.max) else { throw PolishExecutionError.contextExceeded }
        try verifyTensors(graph.inputs, descriptions: model.modelDescription.inputDescriptionsByName)
        try verifyTensors(graph.outputs, descriptions: model.modelDescription.outputDescriptionsByName)
        let states = model.modelDescription.stateDescriptionsByName
        guard Set(states.keys) == Set(graph.states.map(\.name)), graph.states.allSatisfy({ tensor in
            states[tensor.name]?.stateConstraint?.bufferShape == tensor.shape
                && states[tensor.name]?.stateConstraint?.dataType == tensor.dataType.coreML
        }) else { throw ValidationError.incompatibleModel }

        let state = model.makeState()
        let ids = try MLMultiArray(shape: [1, 1], dataType: .int32)
        let position = try MLMultiArray(shape: [1], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, 1, 1, NSNumber(value: context)], dataType: .float32)
        let maskBuffer = mask.dataPointer.assumingMemoryBound(to: Float.self)
        for index in 0..<context { maskBuffer[index] = -10000 }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids), "position": MLFeatureValue(multiArray: position),
            "causal_mask": MLFeatureValue(multiArray: mask)
        ])
        var offset = 0
        func predict(_ token: Int32) async throws -> Int32 {
            try Task.checkCancellation()
            guard deadline.instant > .now else { throw PolishExecutionError.timedOut }
            guard offset < context else { throw PolishExecutionError.contextExceeded }
            ids[0] = NSNumber(value: token)
            position[0] = NSNumber(value: offset)
            maskBuffer[offset] = 0
            let output = try await model.prediction(from: input, using: state)
            try Task.checkCancellation()
            guard deadline.instant > .now else { throw PolishExecutionError.timedOut }
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                throw ValidationError.incompatibleModel
            }
            offset += 1
            return try Self.greedyToken(from: logits, vocabularySize: vocabulary)
        }
        var next: Int32 = 0
        for token in inputTokens { next = try await predict(token) }
        var output: [Int32] = []
        output.reserveCapacity(maximumNewTokens)
        for index in 0..<maximumNewTokens {
            try Task.checkCancellation()
            guard deadline.instant > .now else { throw PolishExecutionError.timedOut }
            if endTokenIDs.contains(next) { return output }
            output.append(next)
            if index + 1 < maximumNewTokens { next = try await predict(next) }
        }
        throw PolishExecutionError.outputTruncated
    }

    static func greedyToken(from logits: MLMultiArray, vocabularySize: Int) throws -> Int32 {
        guard vocabularySize > 0, vocabularySize <= Int(Int32.max),
              logits.shape == [1, NSNumber(value: vocabularySize)], logits.dataType == .float32,
              let stride = logits.strides.last?.intValue, stride > 0,
              !stride.multipliedReportingOverflow(by: vocabularySize - 1).overflow else {
            throw ValidationError.invalidTensor
        }
        let values = logits.dataPointer.assumingMemoryBound(to: Float.self)
        var best = 0, score = -Float.infinity
        for index in 0..<vocabularySize {
            if index.isMultiple(of: 512) { try Task.checkCancellation() }
            let value = values[index * stride]
            guard value.isFinite else { throw ValidationError.invalidTensor }
            if value > score { best = index; score = value }
        }
        return Int32(best)
    }

    private func checkedURL(_ path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.contains("\\"), !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ValidationError.invalidPath
        }
        let url = directory.appendingPathComponent(path).standardizedFileURL
        guard url.resolvingSymlinksInPath().path.hasPrefix(directory.path + "/") else { throw ValidationError.invalidPath }
        for end in 1...components.count {
            let prefix = directory.appendingPathComponent(components.prefix(end).joined(separator: "/"))
            guard let attributes = try? prefix.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  attributes.isSymbolicLink != true else { throw ValidationError.invalidPath }
        }
        return url
    }

    private func verifyFiles() throws {
        for (path, expected) in manifest.files {
            try Task.checkCancellation()
            guard expected.utf8.count == 64,
                  expected.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                throw ValidationError.invalidManifest
            }
            let url = try checkedURL(path)
            guard let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  properties.isRegularFile == true, let size = properties.fileSize, size > 0 else {
                throw ValidationError.missingFile
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                try Task.checkCancellation()
                hash.update(data: bytes)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw ValidationError.hashMismatch }
        }
    }

    private func verifyGraphFiles(_ path: String) throws {
        let url = try checkedURL(path)
        if url.pathExtension == "mlmodel" {
            guard manifest.files[path] != nil else { throw ValidationError.missingFile }
            return
        }
        guard let enumeration = FileManager.default.enumerator(at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw ValidationError.missingFile }
        var count = 0
        for case let file as URL in enumeration {
            try Task.checkCancellation()
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else { throw ValidationError.invalidPath }
            if properties.isRegularFile == true {
                // macOS enumeration can spell /tmp as /private/tmp; match the normalized root.
                let normalized = file.standardizedFileURL.path
                guard normalized.hasPrefix(directory.path + "/") else { throw ValidationError.invalidPath }
                let relative = String(normalized.dropFirst(directory.path.count + 1))
                guard manifest.files[relative] != nil else { throw ValidationError.missingFile }
                count += 1
            }
        }
        guard count > 0 else { throw ValidationError.missingFile }
    }

    private func verifyTensors(_ tensors: [Tensor], descriptions: [String: MLFeatureDescription]) throws {
        // shortcut: fixed-shape arrays only; add flexible bounds for a verified export that needs them.
        guard Set(descriptions.keys) == Set(tensors.map(\.name)) else { throw ValidationError.incompatibleModel }
        for tensor in tensors {
            guard let description = descriptions[tensor.name], description.type == .multiArray,
                  let constraint = description.multiArrayConstraint,
                  constraint.dataType == tensor.dataType.coreML,
                  constraint.shape.map(\.intValue) == tensor.shape else { throw ValidationError.incompatibleModel }
        }
    }
}
