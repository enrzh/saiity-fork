// Run after a simulator Debug build: swift scripts/test-dictation-result-recovery.swift <udid> <derived-data>
import Foundation
guard CommandLine.arguments.count == 3 else { fatalError("Pass simulator ID and derived-data path") }
let udid = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let extensionPath = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let program = #"""
import UIKit
import DictusCore
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
        func deliver(_ text: String, original: String) {
            state.invalidateDictationUndo(reason: "fixture-reset")
            host.proxy.text = "Prefix "
            let request = DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
                .bound(sessionID: UUID().uuidString, generation: 1, clientIdentifier: host.proxy.documentIdentifier.uuidString)
            request.persist(to: defaults)
            DictationDeliveryStore.publishReady(text: text, request: request, to: defaults, originalText: original)
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
        print("PASS: live delivery, recovery, field handoff/pending delivery and at-most-once repeated notifications")
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
    "-I", "DictusKeyboard/Vendored/AOSPTrie/bridge", source.path, extensionPath + "/DictusKeyboard.debug.dylib",
    "-Xlinker", "-rpath", "-Xlinker", extensionPath, "-o", binary.path])
_ = try run(["simctl", "spawn", udid, binary.path])
