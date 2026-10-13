import Foundation

/// Owned byte-level BPE for the verified Qwen 2.5 tokenizer contract.
public struct BytePairTokenizer: Sendable {
    public enum TokenizerError: Error, Equatable, LocalizedError {
        case unsupportedConfiguration, invalidVocabulary, unknownToken
        public var errorDescription: String? {
            switch self {
            case .unsupportedConfiguration: return "The native tokenizer configuration is unsupported."
            case .invalidVocabulary: return "The native tokenizer vocabulary or merge rules are invalid."
            case .unknownToken: return "The native model returned a token outside its tokenizer vocabulary."
            }
        }
    }

    private struct Document: Decodable {
        struct Model: Decodable { let vocab: [String: Int32]; let merges: [String] }
        struct AddedToken: Decodable {
            let id: Int32
            let content: String
            let single_word: Bool
            let lstrip: Bool
            let rstrip: Bool
            let normalized: Bool
            let special: Bool
        }
        let model: Model
        let added_tokens: [AddedToken]
    }
    private struct Merge: Sendable { let rank: Int; let token: Int32 }
    private let split: NSRegularExpression
    private let addedTokenSplit: NSRegularExpression?
    private let addedTokens: [String: Int32]
    private let byteTokens: [Int32]
    private let bytesByToken: [Int32: [UInt8]]
    private let merges: [UInt64: Merge]

    public init(directory: URL) throws {
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("tokenizer.json")
        guard let properties = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              properties.isRegularFile == true, properties.isSymbolicLink != true,
              let size = properties.fileSize, size > 0, size <= 64 * 1024 * 1024 else {
            throw TokenizerError.unsupportedConfiguration
        }
        let data = try Data(contentsOf: url)
        let pattern = #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
        let byteLevel: [String: Any] = ["type": "ByteLevel", "add_prefix_space": false,
                                      "trim_offsets": false, "use_regex": false]
        let pretokenizer: [String: Any] = ["type": "Sequence", "pretokenizers": [
            ["type": "Split", "pattern": ["Regex": pattern], "behavior": "Isolated", "invert": false], byteLevel]]
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] as? String == "1.0", json["truncation"] is NSNull, json["padding"] is NSNull,
              let normalizer = json["normalizer"] as? NSDictionary, normalizer.isEqual(to: ["type": "NFC"]),
              let pre = json["pre_tokenizer"] as? NSDictionary, pre.isEqual(to: pretokenizer),
              let post = json["post_processor"] as? NSDictionary, post.isEqual(to: byteLevel),
              let decoder = json["decoder"] as? NSDictionary, decoder.isEqual(to: byteLevel),
              let model = json["model"] as? [String: Any], model["type"] as? String == "BPE",
              model["dropout"] is NSNull, model["unk_token"] is NSNull,
              model["continuing_subword_prefix"] as? String == "", model["end_of_word_suffix"] as? String == "",
              model["fuse_unk"] as? Bool == false, model["byte_fallback"] as? Bool == false,
              model["ignore_merges"] == nil || model["ignore_merges"] is NSNull || model["ignore_merges"] as? Bool == false,
              Set(model.keys).isSubset(of: ["type", "dropout", "unk_token", "continuing_subword_prefix",
                "end_of_word_suffix", "fuse_unk", "byte_fallback", "ignore_merges", "vocab", "merges"]),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            throw TokenizerError.unsupportedConfiguration
        }

        // Reversible byte alphabet: visible Latin-1 scalars, then U+0100 onward for the remaining bytes.
        var alphabet: [UInt8: Unicode.Scalar] = [:]
        var nextScalar: UInt32 = 256
        for byte in UInt16(0)...255 {
            let visible = (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            guard let scalar = Unicode.Scalar(visible ? UInt32(byte) : nextScalar) else {
                throw TokenizerError.invalidVocabulary
            }
            alphabet[UInt8(byte)] = scalar
            if !visible { nextScalar += 1 }
        }
        let reverseAlphabet = Dictionary(uniqueKeysWithValues: alphabet.map { ($0.value, $0.key) })
        let vocabulary = document.model.vocab
        var bytes: [Int32: [UInt8]] = [:]
        for (token, id) in vocabulary {
            if bytes.count.isMultiple(of: 512) { try Task.checkCancellation() }
            let decoded = token.unicodeScalars.compactMap { reverseAlphabet[$0] }
            guard id >= 0, !token.isEmpty, decoded.count == token.unicodeScalars.count,
                  bytes.updateValue(decoded, forKey: id) == nil else { throw TokenizerError.invalidVocabulary }
        }
        var initialTokens: [Int32] = []
        for byte in UInt16(0)...255 {
            guard let scalar = alphabet[UInt8(byte)], let id = vocabulary[String(scalar)] else {
                throw TokenizerError.invalidVocabulary
            }
            initialTokens.append(id)
        }

        var rules: [UInt64: Merge] = [:]
        var mergedIDs = Set<Int32>()
        var availableIDs = Set(initialTokens)
        for (rank, rule) in document.model.merges.enumerated() {
            if rank.isMultiple(of: 512) { try Task.checkCancellation() }
            let pair = rule.split(separator: " ", omittingEmptySubsequences: false)
            guard pair.count == 2, let left = vocabulary[String(pair[0])], let right = vocabulary[String(pair[1])],
                  availableIDs.contains(left), availableIDs.contains(right),
                  let token = vocabulary[pair.joined()], mergedIDs.insert(token).inserted,
                  rules.updateValue(Merge(rank: rank, token: token), forKey: Self.pairKey(left, right)) == nil else {
                throw TokenizerError.invalidVocabulary
            }
            availableIDs.insert(token)
        }
        guard mergedIDs == Set(vocabulary.values).subtracting(initialTokens) else {
            throw TokenizerError.invalidVocabulary
        }
        var additions: [String: Int32] = [:]
        for token in document.added_tokens {
            guard token.id >= 0, !token.content.isEmpty, token.content.unicodeScalars.allSatisfy({ $0.isASCII }),
                  !token.single_word, !token.lstrip, !token.rstrip, !token.normalized,
                  additions.updateValue(token.id, forKey: token.content) == nil,
                  bytes.updateValue(Array(token.content.utf8), forKey: token.id) == nil else {
                throw TokenizerError.unsupportedConfiguration
            }
        }
        let alternatives = additions.keys.sorted {
            $0.utf8.count == $1.utf8.count ? $0 < $1 : $0.utf8.count > $1.utf8.count
        }.map(NSRegularExpression.escapedPattern(for:))
        split = try NSRegularExpression(pattern: pattern)
        addedTokenSplit = alternatives.isEmpty ? nil : try NSRegularExpression(pattern: alternatives.joined(separator: "|"))
        addedTokens = additions
        byteTokens = initialTokens
        bytesByToken = bytes
        merges = rules
        try Task.checkCancellation()
    }

    public func encode(_ text: String) throws -> [Int32] {
        try Task.checkCancellation()
        let source = text as NSString
        var tokens: [Int32] = []
        var position = 0
        for match in addedTokenSplit?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? [] {
            try appendOrdinary(source.substring(with: NSRange(location: position, length: match.range.location - position)), to: &tokens)
            guard let id = addedTokens[source.substring(with: match.range)] else { throw TokenizerError.unknownToken }
            tokens.append(id)
            position = NSMaxRange(match.range)
        }
        try appendOrdinary(source.substring(from: position), to: &tokens)
        try Task.checkCancellation()
        return tokens
    }

    private func appendOrdinary(_ text: String, to tokens: inout [Int32]) throws {
        let normalized = text.precomposedStringWithCanonicalMapping
        let source = normalized as NSString
        var position = 0
        for match in split.matches(in: normalized, range: NSRange(location: 0, length: source.length)) {
            try Task.checkCancellation()
            guard match.range.location == position else { throw TokenizerError.unsupportedConfiguration }
            var pieces = source.substring(with: match.range).utf8.map { byteTokens[Int($0)] }
            // shortcut: scan distinct ranks per pretoken; use a ranked queue if varied long tokens warrant it.
            while pieces.count > 1 {
                try Task.checkCancellation()
                var best: (left: Int32, right: Int32, merge: Merge)?
                for index in 0..<(pieces.count - 1) {
                    if index.isMultiple(of: 512) { try Task.checkCancellation() }
                    if let merge = merges[Self.pairKey(pieces[index], pieces[index + 1])],
                       merge.rank < (best?.merge.rank ?? Int.max) {
                        best = (pieces[index], pieces[index + 1], merge)
                    }
                }
                guard let best else { break }
                // Validated rule order makes every new pair's rank higher than this rank.
                var combined: [Int32] = []
                combined.reserveCapacity(pieces.count)
                var index = 0
                while index < pieces.count {
                    if index.isMultiple(of: 512) { try Task.checkCancellation() }
                    if index + 1 < pieces.count, pieces[index] == best.left, pieces[index + 1] == best.right {
                        combined.append(best.merge.token)
                        index += 2
                    } else {
                        combined.append(pieces[index])
                        index += 1
                    }
                }
                pieces = combined
            }
            tokens.append(contentsOf: pieces)
            position = NSMaxRange(match.range)
        }
        guard position == source.length else { throw TokenizerError.unsupportedConfiguration }
    }

    private static func pairKey(_ left: Int32, _ right: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: left)) << 32 | UInt64(UInt32(bitPattern: right))
    }

    /// Retain these raw bytes until a full UTF-8 sequence is available when streaming.
    public func tokenBytes(for id: Int32) throws -> [UInt8] {
        guard let bytes = bytesByToken[id] else { throw TokenizerError.unknownToken }
        return bytes
    }

    public func decode(_ ids: [Int32]) throws -> String {
        try Task.checkCancellation()
        var bytes: [UInt8] = []
        for id in ids {
            try Task.checkCancellation()
            bytes.append(contentsOf: try tokenBytes(for: id))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
