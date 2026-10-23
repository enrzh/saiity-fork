// Run after a simulator Debug build: swift scripts/test-dictation-result-recovery.swift <udid> <derived-data>
import Foundation
guard CommandLine.arguments.count == 3 else { fatalError("Pass simulator ID and derived-data path") }
let udid = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let extensionPath = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let program = #"""
import UIKit
import SyllivraKernel
@testable import DictusKeyboard

@MainActor final class Proxy: NSObject, UITextDocumentProxy {
    var text = "Prefix "
    var documentIdentifier = UUID()
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? = ""
    var selectedText: String?
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !text.isEmpty }
    var deletionCount = 0
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast(); deletionCount += 1 } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}
@MainActor final class Host: UIInputViewController {
    let proxy = Proxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
@main @MainActor struct RecoveryCheck {
    static func main() {
        let defaults = AppGroup.defaults
        let keys = [SharedKeys.historyEnabled, SharedKeys.recentDictations, SharedKeys.dictationStatus,
            SharedKeys.dictationLanguageRequest, SharedKeys.dictationDelivery, SharedKeys.lastTranscription,
            SharedKeys.lastTranscriptionTimestamp, SharedKeys.modelReady, SharedKeys.modelLoadState,
            SharedKeys.modelLoadStateTimestamp, SharedKeys.modelLoadFailure]
            + ["mode", "target", "sessionID", "generation", "clientIdentifier", "source"]
                .map { DictationLanguageRequest.appGroupKey + "." + $0 }
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (index, key) in keys.enumerated() {
                if let value = saved[index] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        defaults.set(true, forKey: SharedKeys.modelReady)
        defaults.set(ModelLoadState.ready.rawValue, forKey: SharedKeys.modelLoadState)
        let host = Host(), window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        window.rootViewController = host
        window.isHidden = false
        let state = KeyboardState.shared
        state.controller = host
        func deliver(_ text: String, original: String, translationOutcome: String? = nil) {
            state.invalidateDictationUndo(reason: "fixture-reset")
            host.proxy.text = "Prefix "
            let request = DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
                .bound(sessionID: UUID().uuidString, generation: 1, clientIdentifier: host.proxy.documentIdentifier.uuidString)
            request.persist(to: defaults)
            var timings = DictationRuntimeMetrics(sessionID: request.sessionID ?? "fixture")
            if let translationOutcome { timings.setContext("translationOutcome", value: translationOutcome) }
            DictationDeliveryStore.publishReady(text: text, request: request, to: defaults, timings: timings, originalText: original)
            state.registerControllerAppearance(controllerID: "fixture")
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            precondition(state.dictationUndoAvailable)
        }
        deliver("Hello. ", original: "uh hello")
        precondition(host.proxy.text == "Prefix Hello. ")
        let menu = state.dictationResultMenuItems().compactMap { $0 as? UIMenu }.flatMap(\.children)
        precondition(menu.contains { $0.title == "Restore original" })
        state.restoreOriginalDictation()
        precondition(host.proxy.text == "Prefix uh hello ")

        let original = "明日の予定を確認します。\t\nCafe\u{301} — API_240"
        deliver(original + " ", original: original, translationOutcome: "originalKept:rejectedOutput")
        precondition(host.proxy.text == "Prefix " + original + " ", "Unicode or separators changed during fallback delivery")
        precondition(state.dictationResultMenuItems().contains { $0.title == "Translation unavailable — original kept" },
                     "Keyboard labelled an unverified translation successful")
        for model in [QwenASRModel.small, .large] {
            let description = ModelInfo.forIdentifier(model.rawValue)!.localizedDescription
            precondition(description.contains("Qwen") && description.contains("foreground"), "Qwen card described Whisper")
        }
        for (text, hint, expected) in [
            ("APIとbuild_240の設定を確認します。", "zh", "ja"),
            ("ﾐｰﾃｨﾝｸﾞの予定を確認します。", "zh", "ja"),
            ("오늘 漢字 자료를 확인하고 회의 일정을 정합니다.", "zh", "ko")
        ] {
            precondition(SpeechLanguageEvidence.baseCode(SpeechLanguageEvidence.sourceLanguage(in: text, hint: hint)) == expected,
                         "Native language policy split a coherent phrase")
        }
        precondition(SpeechLanguageEvidence.sourceLanguage(in: "a escola", hint: "en") == nil)
        precondition(PolishPostpass.cleanupFloor("a escola", language: nil) == "A escola")
        precondition(PolishPostpass.cleanupFloor("John, actually Jean", language: .portuguese) == "John, actually Jean")
        precondition(PolishPostpass.cleanupFloor("[API_240] [HTTP] [USD] Cafe\u{301}", language: nil) == "[API_240] [HTTP] [USD] Cafe\u{301}")
        precondition(TranslationOutcome.resolved(original: "Rendez-vous à 12:30.", translated: "Meet at 30:12.",
            clientIdentifierMatches: true, target: .english).resolvedText == "Rendez-vous à 12:30.")
        precondition(TranslationOutcome.resolved(original: "请支付25欧元。", translated: "请支付52欧元。",
            clientIdentifierMatches: true, target: .chineseSimplified).resolvedText == "请支付25欧元。")
        precondition(TranslationOutcome.resolved(original: "Pay €25.", translated: "支付25欧元。",
            clientIdentifierMatches: true, target: .chineseSimplified) == .translated("支付25欧元。"))
        precondition(TranslationOutcome.resolved(original: "我們今天無法完成全部付款請稍後再試。",
            translated: "我们今天无法完成全部付款请稍后再试。", clientIdentifierMatches: true,
            target: .chineseSimplified).fallbackReason == nil)

        deliver("Hello. ", original: "uh hello")
        host.proxy.documentIdentifier = UUID()
        let count = host.proxy.deletionCount
        state.restoreOriginalDictation()
        state.performDictationUndo()
        precondition(host.proxy.deletionCount == count, "Changed document was modified")

        deliver("Hello. ", original: "uh hello")
        host.proxy.text += "new typing"
        state.restoreOriginalDictation()
        precondition(host.proxy.text.hasSuffix("new typing"), "New typing was removed")

        deliver("Hello. ", original: "uh hello")
        host.proxy.selectedText = "selected"
        state.restoreOriginalDictation()
        precondition(host.proxy.text == "Prefix Hello. ", "Selection allowed stale replacement")
        host.proxy.selectedText = nil
        state.invalidateDictationUndo(reason: "pending-fixture")
        let originalPrefix = host.proxy.text
        let request = DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
            .bound(sessionID: UUID().uuidString, generation: 1, clientIdentifier: host.proxy.documentIdentifier.uuidString)
        request.persist(to: defaults)
        DictationDeliveryStore.publishReady(text: "Pending. ", request: request, to: defaults, originalText: "pending")
        let other = Host(), otherWindow = UIWindow(frame: window.frame)
        otherWindow.rootViewController = other
        otherWindow.isHidden = false
        state.controller = other
        state.registerControllerAppearance(controllerID: "other-field")
        precondition(other.proxy.text == "Prefix ", "Result was inserted into another field")
        precondition(host.proxy.text == originalPrefix, "The old controller received a result during handoff")
        precondition(defaults.data(forKey: SharedKeys.dictationDelivery) != nil, "Unusable target consumed recovery text")
        state.controller = host
        state.registerControllerAppearance(controllerID: "original-field")
        state.registerControllerAppearance(controllerID: "original-field")
        precondition(host.proxy.text == originalPrefix + "Pending. ", "Pending delivery was lost or duplicated")
        otherWindow.isHidden = true
        state.invalidateDictationUndo(reason: "fixture-end")
        window.isHidden = true
        print("PASS: live Unicode/fallback delivery, Qwen copy, recovery, field handoff/pending delivery and at-most-once repeated notifications")
    }
}
"""#
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-recovery-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("check")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); process.arguments = args
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Failed: \(args.first ?? "command")") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator", "-I", products,
    source.path, "DictusApp/Extensions/ModelInfo+Localized.swift", extensionPath + "/DictusKeyboard.debug.dylib",
    "-Xlinker", "-rpath", "-Xlinker", extensionPath, "-o", binary.path])
_ = try run(["simctl", "spawn", udid, binary.path])
