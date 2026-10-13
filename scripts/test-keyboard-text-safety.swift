// Production keyboard text checks; no app launch, microphone or voice models.
import Foundation
guard CommandLine.arguments.count >= 3 else { fatalError("Pass QA simulator ID and derived-data path") }
let simulator = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let keyboard = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let loaderPath = "DictusKeyboard/TextPrediction/AOSPTrieEngine.swift"
let loader: String
if CommandLine.arguments.contains("--baseline-loader") {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["show", "HEAD:" + loaderPath]; process.standardOutput = pipe
    try process.run(); loader = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit(); precondition(process.terminationStatus == 0)
} else { loader = try String(contentsOfFile: loaderPath, encoding: .utf8) }
// Pause the real loader after its generation check, without subclassing NSBundle's class cluster.
let loaderWithTimingHook = loader.replacingOccurrences(of: "final class AOSPTrieEngine {",
    with: "final class AOSPTrieEngine {\n    var beforeMapping: (() -> Void)?\n    var beforePublication: (() -> Void)?")
    .replacingOccurrences(of: "            guard let path = bundle.path(",
                         with: "            self.beforeMapping?()\n            guard let path = bundle.path(")
    .replacingOccurrences(of: "                if success {\n                    self.wordCount",
                         with: "                self.beforePublication?()\n                if success {\n                    self.wordCount")
    .replacingOccurrences(of: "                let completed = self.loadGeneration.withLock",
                         with: "                self.beforePublication?()\n                let completed = self.loadGeneration.withLock")
let program = loaderWithTimingHook + #"""
import UIKit
import SyllivraKernel
@testable import DictusKeyboard

final class Proxy: NSObject, UITextDocumentProxy {
    let documentIdentifier = UUID()
    var text = ""
    var keyboardType = UIKeyboardType.default
    var textContentType: UITextContentType? = nil
    var autocorrectionType = UITextAutocorrectionType.yes
    var spellCheckingType = UITextSpellCheckingType.yes
    var isSecureTextEntry = false
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !text.isEmpty }
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
func waitFor(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Background prediction did not settle")
}
let defaults = AppGroup.defaults
let keys = [SharedKeys.language, SharedKeys.keyboardLanguageSelection, SharedKeys.spokenLanguages,
    SharedKeys.autocorrectEnabled, "dictus.userDictionary", "dictus.userDictionary.pending",
    "dictus.userDictionary.lastUsed", "dictus.userDictionary.prunedTrieDuplicates"]
let saved = keys.map { defaults.object(forKey: $0) }
defer {
    for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
    UserDictionary.shared.reload()
}
KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
defaults.set([], forKey: SharedKeys.spokenLanguages)
defaults.set(true, forKey: SharedKeys.autocorrectEnabled)
defaults.set(true, forKey: "dictus.userDictionary.prunedTrieDuplicates")
let state = SuggestionState.shared
state.setLanguage("fr")
let queue = Mirror(reflecting: state).children.first { $0.label == "suggestionQueue" }!.value as! DispatchQueue
queue.sync {}
waitFor { !TextPredictionEngine.shared.dictionaryLoadInFlight }
let proxy = Proxy()
UserDictionary.shared.forget("bonjour")
UserDictionary.shared.forget("bonjor")
for input in ["bonjor.", "bonjor,", "\"bonjor\"", "français".decomposedStringWithCanonicalMapping + "."] {
    state.clear(resetLanguage: false)
    proxy.text = input
    state.updateAdaptiveTouchPrediction(context: input, policy: .allowed)
    queue.sync {}
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    state.handleSpace(proxy: proxy)
    precondition(proxy.text == input + " ", "Punctuation or normalization was deleted: \(proxy.text)")
}
FileHandle.standardError.write(Data("CHECK: punctuation preserved\n".utf8))
for _ in 0..<2 {
    state.clear(resetLanguage: false)
    proxy.text = "bonjour"
    state.updateAdaptiveTouchPrediction(context: proxy.text, policy: .allowed)
    queue.sync {}
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    state.handleSpace(proxy: proxy)
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
}
precondition(!UserDictionary.shared.isLearned("bonjour"), "Known dictionary word was learned")
FileHandle.standardError.write(Data("CHECK: known word remained unlearned\n".utf8))
let native = AOSPTrieEngine()
let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
var firstMapping = true
native.beforeMapping = {
    if firstMapping { firstMapping = false; entered.signal(); precondition(release.wait(timeout: .now() + 5) == .success) }
}
native.load(language: "fr", bundle: Bundle(path: "KEYBOARD_BUNDLE")!)
precondition(entered.wait(timeout: .now() + 5) == .success)
native.load(language: "it", bundle: Bundle(path: "KEYBOARD_BUNDLE")!)
release.signal()
waitFor { !native.isLoading }
precondition(!native.isLoaded && native.mountedLanguage == nil, "Older language remounted after latest missing dictionary")
let publicationNative = AOSPTrieEngine()
var pausePublication = true
var obsoleteCompletion = false
publicationNative.beforePublication = {
    if pausePublication {
        pausePublication = false
        let registered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            publicationNative.load(language: "it", bundle: Bundle(path: "KEYBOARD_BUNDLE")!)
            registered.signal()
        }
        precondition(registered.wait(timeout: .now() + 5) == .success)
    }
}
publicationNative.load(language: "fr", bundle: Bundle(path: "KEYBOARD_BUNDLE")!) { obsoleteCompletion = $0 }
waitFor { !publicationNative.isLoading }
precondition(!pausePublication && !obsoleteCompletion && publicationNative.mountedLanguage == nil,
             "A stale completion marked a newer language ready")
let began = CFAbsoluteTimeGetCurrent()
let cold = TextPredictionEngine(bundle: Bundle(path: "KEYBOARD_BUNDLE")!)
let coldMS = (CFAbsoluteTimeGetCurrent() - began) * 1000
precondition(cold.enabledDictionaryLanguages.isEmpty, "Engine initializer mounted dictionaries synchronously")
print("PASS: production punctuation/Unicode safety, known-word learning and serialized missing-language replacement")
print("MEASURE: cold engine construction = \(coldMS)ms on simulator; dictionaries initialize later on the prediction queue")
"""#.replacingOccurrences(of: "KEYBOARD_BUNDLE", with: keyboard)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-text-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("check")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); process.arguments = args
    if capture { process.standardOutput = pipe }
    try process.run(); let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data(); process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Failed: \(args.first ?? "command")")
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["--sdk", "iphonesimulator", "swiftc", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator", "-I", products,
    "-I", "DictusKeyboard/Vendored/AOSPTrie/bridge", source.path, keyboard + "/DictusKeyboard.debug.dylib",
    "-Xlinker", "-rpath", "-Xlinker", keyboard, "-o", binary.path])
_ = try run(["simctl", "spawn", simulator, binary.path])
