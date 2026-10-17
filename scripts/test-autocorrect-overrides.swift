// Off-device checks of production correction/reconciliation methods with in-memory proxy and dictionary doubles.
// Run from the repository: swift scripts/test-autocorrect-overrides.swift <scratch> <artifacts>
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Pass scratch and artifact directories") }
let scratch = URL(fileURLWithPath: CommandLine.arguments[1])
let artifacts = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try String(contentsOfFile: "DictusKeyboard/TextPrediction/SuggestionState.swift", encoding: .utf8)
func section(_ start: String, _ end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else { fatalError("Missing production section: \(start)") }
    return String(source[lower.lowerBound..<upper.lowerBound])
}
let types = section("struct AutocorrectState {", "/// Observable suggestion state")
let commit = section("    private struct SpaceCommit {", "    private var pendingAutocorrection:")
let space = section("    func handleSpace(proxy:", "    /// Drop a stale hit bias")
let reconcile = section("    func noteSelectionChanged(proxy:", "    /// Applies a visible suggestion")
let extract = section("    private func extractLastWord(from", "\n}")
let replacement = try String(contentsOfFile: "SyllivraKernel/Sources/SyllivraKernel/AutocorrectReplacement.swift", encoding: .utf8)
let program = #"""
import Foundation
// PRODUCTION_TYPES
// PRODUCTION_REPLACEMENT
struct Policy { var suggestionsAllowed = true; var autocorrectAllowed = true }
final class Proxy {
    var text = ""
    var after = ""
    var selectedText: String?
    var identifier: UUID? = UUID()
    var secure = false
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { after }
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}
typealias UITextDocumentProxy = Proxy
enum HostInputTraits {
    static func policy(for proxy: Proxy) -> Policy { Policy(suggestionsAllowed: !proxy.secure, autocorrectAllowed: !proxy.secure) }
    static func documentIdentifier(for proxy: Proxy) -> UUID? { proxy.identifier }
}
enum SupportedLanguage { static var active: Self { .english }; case english; var rawValue: String { "en" } }
enum AppGroup { static let defaults = UserDefaults(suiteName: "unused-autocorrect-fixture")! }
enum SpokenLanguagePreferences { static func load(from: UserDefaults) -> [String] { [] } }
enum SnippetStore { static func expansion(for word: String, from: UserDefaults) -> String? { nil } }
enum TypingCommit { static func accepts(typed: String, correction: String) -> Bool { typed != correction } }
enum DictationVocabulary { static let maxTermCharacters = 64 }
enum HapticFeedback { static func playInputClick() {} }
final class UserDictionary {
    static let shared = UserDictionary()
    var words: Set<String> = []
    func isLearned(_ word: String) -> Bool { words.contains(word.lowercased()) }
    @discardableResult func learn(_ word: String) -> Bool { words.insert(word.lowercased()).inserted }
    @discardableResult func recordUsage(_ word: String) -> Bool { false }
}
final class Engine {
    func shouldSkipTokenPrediction(for word: String) -> Bool { false }
    func isUnknownToDictionary(_ word: String) -> Bool { true }
}
final class State {
    // PRODUCTION_COMMIT
    private var pendingAutocorrection: PendingAutocorrection?
    private var spaceCommit: SpaceCommit?
    var hostPolicy = Policy()
    var autocorrectEnabled = true
    var rejectedWords: Set<String> = []
    var pendingUndo: AutocorrectState?
    let engine = Engine()
    let suggestionQueue = DispatchQueue(label: "autocorrect-fixture")
    func clear(resetLanguage: Bool = true) { spaceCommit = nil }
    func noteTypedCharacter(_ character: String) {}
    func prepare(_ word: String, correction: String?, context: String) {
        spaceCommit = SpaceCommit(word: word, correction: correction, isUnknownWord: true,
            contextKey: String(context.suffix(240)), selectedLanguage: "en", spokenLanguages: [])
    }
    // PRODUCTION_SPACE
    // PRODUCTION_RECONCILE
    // PRODUCTION_EXTRACT
}
var failures: [String] = []
func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
func corrected() -> (State, Proxy) {
    UserDictionary.shared.words = []
    let state = State(), proxy = Proxy()
    proxy.text = "we bonjor"
    state.prepare("bonjor", correction: "bonjour", context: proxy.text)
    state.handleSpace(proxy: proxy)
    check(proxy.text == "we bonjour ", "Ordinary correction stopped working")
    return (state, proxy)
}
for (label, emptyFirst, callbacks) in [("restore original", false, 0), ("delete and retype", true, 1), ("duplicate callbacks", false, 3)] {
    let (state, proxy) = corrected()
    for _ in 0..<callbacks { state.reconcilePendingAutocorrection(proxy: proxy) }
    if emptyFirst { proxy.text = "we "; state.reconcilePendingAutocorrection(proxy: proxy) }
    proxy.text = "we bonjor"
    state.prepare("bonjor", correction: "bonjour", context: proxy.text)
    state.noteSelectionChanged(proxy: proxy)
    state.handleSpace(proxy: proxy)
    check(proxy.text == "we bonjor ", "\(label): corrected the restored spelling again")
    check(UserDictionary.shared.isLearned("bonjor"), "\(label): original spelling was not learned")
    state.prepare("bonjor", correction: "bonjour", context: "we bonjor")
    proxy.text = "we bonjor"
    state.handleSpace(proxy: proxy)
    check(proxy.text == "we bonjor ", "\(label): a cached correction overrode learned spelling")
}
for (label, mutate) in [
    ("different document", { (p: Proxy) in p.identifier = UUID() }),
    ("unidentified document", { (p: Proxy) in p.identifier = nil }),
    ("secure field", { (p: Proxy) in p.secure = true }),
    ("moved caret", { (p: Proxy) in p.after = "different trailing text" })
] {
    let (state, proxy) = corrected()
    mutate(proxy)
    proxy.text = "we bonjor "
    state.noteSelectionChanged(proxy: proxy)
    state.reconcilePendingAutocorrection(proxy: proxy)
    check(!UserDictionary.shared.isLearned("bonjor"), "\(label): unrelated or protected text was learned")
}
do {
    let (state, proxy) = corrected()
    proxy.text = "we "
    proxy.selectedText = "bonjour"
    proxy.after = " "
    state.noteSelectionChanged(proxy: proxy)
    proxy.selectedText = nil
    proxy.text = "we bonjor"
    state.noteSelectionChanged(proxy: proxy)
    state.prepare("bonjor", correction: "bonjour", context: proxy.text)
    state.handleSpace(proxy: proxy)
    check(proxy.text == "we bonjor " && UserDictionary.shared.isLearned("bonjor"), "Replacing a selected correction was not respected")
}
for token in ["API_123", "name@example.com", "https://example.com", "abc123"] {
    let (state, proxy) = corrected()
    proxy.text = "we " + token + " "
    state.reconcilePendingAutocorrection(proxy: proxy)
    check(UserDictionary.shared.words.isEmpty, "Unsafe token entered learned vocabulary: \(token)")
}
do {
    let (state, proxy) = corrected()
    proxy.text = "we otherword bonjors"
    state.prepare("bonjors", correction: nil, context: proxy.text)
    state.handleSpace(proxy: proxy)
    check(!UserDictionary.shared.isLearned("bonjors"), "A changed prefix was mistaken for a spelling override")
}
do {
    let (state, proxy) = corrected()
    proxy.text = "we bonjors"
    state.prepare("bonjors", correction: nil, context: proxy.text)
    state.handleSpace(proxy: proxy)
    check(UserDictionary.shared.isLearned("bonjors"), "A deliberate alternative spelling was not learned")
}
if failures.isEmpty {
    print("PASS: restore original, delete/retype, duplicate callbacks, cached learning, alternative spelling and field/privacy guards")
} else {
    for failure in failures { FileHandle.standardError.write(Data(("FAIL: " + failure + "\n").utf8)) }
    exit(1)
}
"""#
    .replacingOccurrences(of: "// PRODUCTION_TYPES", with: types)
    .replacingOccurrences(of: "// PRODUCTION_REPLACEMENT", with: replacement)
    .replacingOccurrences(of: "// PRODUCTION_COMMIT", with: commit)
    .replacingOccurrences(of: "// PRODUCTION_SPACE", with: space)
    .replacingOccurrences(of: "// PRODUCTION_RECONCILE", with: reconcile)
    .replacingOccurrences(of: "// PRODUCTION_EXTRACT", with: extract)
let generated = scratch.appendingPathComponent("overrides.swift")
let binary = scratch.appendingPathComponent("overrides")
try program.write(to: generated, atomically: true, encoding: .utf8)
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["swiftc", "-module-cache-path", scratch.appendingPathComponent("module-cache").path, generated.path, "-o", binary.path]
try compiler.run(); compiler.waitUntilExit()
guard compiler.terminationStatus == 0 else { exit(compiler.terminationStatus) }
let probe = Process()
probe.executableURL = binary
try probe.run(); probe.waitUntilExit()
try FileManager.default.copyItem(at: generated, to: artifacts.appendingPathComponent("production-override-probe.swift"))
exit(probe.terminationStatus)
