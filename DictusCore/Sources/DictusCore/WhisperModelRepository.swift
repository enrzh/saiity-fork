// DictusCore/Sources/DictusCore/WhisperModelRepository.swift
// Single source of truth for where downloaded WhisperKit models live on disk.
import Foundation

/// Resolves the on-disk location of downloaded WhisperKit model variants.
///
/// WHY this type exists (issue #249):
/// The layout `Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier}`
/// was known only to `ModelManager`, which used it for download, delete and cleanup
/// (issue #210). The dictation path had no notion of it and therefore built its
/// `WhisperKitConfig` from the model *name* with `download: true`. WhisperKit then
/// resolved the identifier against the Hugging Face hub over the network, so a cold
/// start with no connectivity failed with `downloadError` even though the model was
/// already on the device. Both sides now resolve the folder through this type.
///
/// WHY `Documents/huggingface`:
/// WhisperKit stores models through `HubApi`, whose default download base is the
/// process's Documents directory plus `huggingface`, and whose repo layout is
/// `<base>/models/<repo id>/<variant>`. `ModelRepoDownloader` writes the exact same
/// layout, and `WhisperKitConfig(modelFolder:)` reads it back.
///
/// IMPORTANT: the Documents directory is per-process. Only DictusApp downloads and
/// loads models, so these helpers must be called from the app. The keyboard
/// extension has its own (empty) Documents directory and would always see the
/// models as missing.
public enum WhisperModelRepository {

    /// Hugging Face repository hosting the Core ML Whisper variants.
    public static let repositoryID = "argmaxinc/whisperkit-coreml"

    /// Repository location relative to the Documents directory.
    public static let relativeRepositoryPath = "huggingface/models/argmaxinc/whisperkit-coreml"

    public static let downloadReceiptFileName = ".dictus-download-receipt.json"

    /// Documents directory of the current process, or `nil` when unavailable.
    public static var defaultDocumentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Root of the local WhisperKit repository.
    /// - Parameter documentsDirectory: Override for tests. `nil` uses the process's
    ///   own Documents directory.
    public static func repositoryURL(documentsDirectory: URL? = nil) -> URL? {
        guard let documents = documentsDirectory ?? defaultDocumentsDirectory else { return nil }
        return documents.appendingPathComponent(relativeRepositoryPath, isDirectory: true)
    }

    /// Folder a variant occupies once downloaded, whether or not it exists yet.
    /// Used by download, delete and cleanup, which need the path even when empty.
    public static func modelFolderURL(
        for identifier: String,
        documentsDirectory: URL? = nil
    ) -> URL? {
        repositoryURL(documentsDirectory: documentsDirectory)?
            .appendingPathComponent(identifier, isDirectory: true)
    }

    /// Folder of a variant that is actually usable offline, or `nil` when the model
    /// is absent or the folder holds no compiled Core ML bundle.
    ///
    /// Callers on the dictation path must treat `nil` as "ask the user to download
    /// it in the model manager" rather than downloading it themselves (issue #249).
    public static func installedModelFolderURL(
        for identifier: String,
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let folder = modelFolderURL(for: identifier, documentsDirectory: documentsDirectory) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let bundles = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
        let configuration = folder.appendingPathComponent("config.json")
        guard nonemptyFile(configuration),
              let size = try? configuration.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4_000_000,
              let data = try? Data(contentsOf: configuration),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
              bundles.allSatisfy({ bundle in
                  let url = folder.appendingPathComponent(bundle, isDirectory: true)
                  let needsWeights = bundle != "MelSpectrogram.mlmodelc"
                  let hasProgram = nonemptyFile(url.appendingPathComponent("model.mil"))
                      && (!needsWeights || nonemptyFile(url.appendingPathComponent("weights/weight.bin")))
                  let hasNetwork = nonemptyFile(url.appendingPathComponent("model.espresso.net"))
                      && (!needsWeights || nonemptyFile(url.appendingPathComponent("model.espresso.weights")))
                  return ParakeetModelRepository.isCompiledModelBundle(url, fileManager: fileManager)
                      && nonemptyFile(url.appendingPathComponent(ParakeetModelRepository.compiledModelMarkerFile))
                      && (hasProgram || hasNetwork)
              }) else {
            return nil
        }
        let receipt = folder.appendingPathComponent(downloadReceiptFileName)
        if fileManager.fileExists(atPath: receipt.path),
           !receiptFilesAreComplete(at: receipt, relativeTo: folder.deletingLastPathComponent(),
                                    requiredPrefix: identifier + "/", fileManager: fileManager) {
            return nil
        }
        return folder
    }

    /// Shared with the downloader so readiness checks the same recorded file sizes offline.
    public static func receiptFilesAreComplete(at receipt: URL, relativeTo directory: URL,
                                              requiredPrefix: String? = nil,
                                              fileManager: FileManager = .default) -> Bool {
        guard let size = try? receipt.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4_000_000,
              let data = try? Data(contentsOf: receipt),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1,
              let files = object["files"] as? [[String: Any]], !files.isEmpty else { return false }
        var paths = Set<String>()
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return files.allSatisfy { file in
            guard let path = file["path"] as? String, let expectedSize = file["size"] as? Int,
                  !path.hasPrefix("/"), !path.isEmpty,
                  !path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }),
                  requiredPrefix.map({ path.hasPrefix($0) }) ?? true,
                  paths.insert(path).inserted else { return false }
            let url = directory.appendingPathComponent(path)
            guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let actualSize = values.fileSize else { return false }
            return expectedSize >= 0 ? actualSize == expectedSize : actualSize > 0
        }
    }

    private static func nonemptyFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    /// Whether the variant is present on disk and loadable without any network access.
    public static func isModelInstalled(
        _ identifier: String,
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        installedModelFolderURL(
            for: identifier,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        ) != nil
    }

    /// Names of the tokenizer repositories cached alongside the models.
    ///
    /// WHY this exists: WhisperKit loads the tokenizer separately from the model,
    /// from `Documents/huggingface/models/openai/whisper-*`, which is populated the
    /// first time a variant is loaded online (the prewarm that follows every
    /// download). It is not part of the variant folder, so a model folder can be
    /// complete while the tokenizer cache is not. This is diagnostic only — the
    /// mapping from variant to tokenizer repo lives inside WhisperKit and is
    /// deliberately not duplicated here. Logged on the dictation load path so an
    /// offline failure can be attributed to the tokenizer rather than the model.
    public static func cachedTokenizerRepositoryNames(
        documentsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let documents = documentsDirectory ?? defaultDocumentsDirectory else { return [] }
        let openAIDirectory = documents
            .appendingPathComponent("huggingface/models/openai", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(atPath: openAIDirectory.path) else {
            return []
        }
        return entries.sorted()
    }
}
