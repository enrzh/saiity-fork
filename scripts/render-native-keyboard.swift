// swift scripts/render-native-keyboard.swift <QA simulator> <derived-data> <output-directory> [--large] [--emoji]
// Production keyboard views, inert text proxy, no touch actions, audio or model loads.
import Foundation

guard CommandLine.arguments.count >= 4 else { fatalError("Pass simulator, derived data and output directory") }
let simulator = CommandLine.arguments[1], derived = CommandLine.arguments[2], output = CommandLine.arguments[3]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let extensionPath = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let large = CommandLine.arguments.contains("--large")
let emojiOnly = CommandLine.arguments.contains("--emoji")
let inset = !CommandLine.arguments.contains("--no-inset")
let topBar = CommandLine.arguments.contains("--top-bar")
let keypadOnly = CommandLine.arguments.contains("--keypad")
let shortcutsOnly = CommandLine.arguments.contains("--shortcuts")
let program = #"""
import UIKit
import SwiftUI
import SyllivraKernel
@testable import DictusKeyboard

final class FixtureProxy: UITextView, UITextDocumentProxy {
    let documentIdentifier = UUID()
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { textInputMode }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
final class FixtureController: KeyboardViewController {
    let proxy = FixtureProxy()
    override var textDocumentProxy: any UITextDocumentProxy { proxy }
}

@main @MainActor struct RenderKeyboard {
    static func main() throws {
        let defaults = AppGroup.defaults
        let keys = [SharedKeys.liquidGlassEnabled, SharedKeys.keyboardInsetEnabled,
                    SharedKeys.keyContainersEnabled, SharedKeys.keyPopupMode,
                    SharedKeys.serviceEnabled, SharedKeys.dictationStatus,
                    SharedKeys.modelReady, SharedKeys.modelLoadState, SharedKeys.keyboardAudioReady,
                    SharedKeys.appProcessHeartbeat,
                    SharedKeys.keyboardIOSStyling, SharedKeys.keyboardTopBarEnabled]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = previous[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: SharedKeys.serviceEnabled)
        defaults.set(TOPBAR, forKey: SharedKeys.keyboardTopBarEnabled)
        defaults.set(true, forKey: SharedKeys.keyContainersEnabled)
        defaults.set(INSET, forKey: SharedKeys.keyboardInsetEnabled)
        defaults.set(KeyPopupMode.off.rawValue, forKey: SharedKeys.keyPopupMode)
        try FileManager.default.createDirectory(atPath: "OUTPUT", withIntermediateDirectories: true)
        var geometry: [String: [String: String]] = [:]
        for dark in [false, true] {
            for glass in [false, true] {
                defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
                for width: CGFloat in [320, 402] {
                    for landscape in [false, true] {
                        let size = landscape ? CGSize(width: width == 320 ? 667 : 852,
                            height: TOPBAR ? 190 : 158)
                                             : CGSize(width: width, height: 300)
                        for page in (SHORTCUTS ? ["letters", "symbols", "board", "ready-board"] : KEYPAD ? ["numbers", "decimal", "phone"] : ["letters", "symbols", "symbols2", "numbers", "phone", "emoji",
                                     "board", "ready-board", "listening", "processing", "failure"]) {
                            if EMOJIONLY && page != "emoji" { continue }
                            if LARGE && !["letters", "emoji", "board", "ready-board", "listening"].contains(page) { continue }
                            // Inert readiness claims only: this renderer never
                            // invokes the app coordinator, audio or model loading.
                            defaults.set(page == "ready-board", forKey: SharedKeys.serviceEnabled)
                            defaults.set(page == "ready-board", forKey: SharedKeys.keyboardAudioReady)
                            defaults.set(page == "ready-board", forKey: SharedKeys.modelReady)
                            defaults.set(ModelLoadState.idle.rawValue, forKey: SharedKeys.modelLoadState)
                            defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.appProcessHeartbeat)
                            let root = UIViewController()
                            let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height + 80)))
                            window.overrideUserInterfaceStyle = dark ? .dark : .light
                            window.rootViewController = root
                            window.makeKeyAndVisible()
                            root.view.backgroundColor = .secondarySystemBackground
                            let field = UILabel(frame: CGRect(x: 18, y: 16, width: size.width - 36, height: 48))
                            field.text = "Message draft · 我們下午再確認一次。"
                            field.font = .systemFont(ofSize: 17)
                            field.textColor = .label
                            field.numberOfLines = 2
                            root.view.addSubview(field)
                            let controller = FixtureController()
                            controller.proxy.keyboardType = page == "phone" ? .phonePad : page == "decimal" ? .decimalPad : page == "numbers" ? .numberPad : .default
                            root.addChild(controller)
                            if LARGE {
                                root.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
                            }
                            root.view.addSubview(controller.view)
                            controller.view.frame = CGRect(x: 0, y: 80, width: size.width, height: size.height)
                            controller.inputView?.frame.size = size
                            controller.didMove(toParent: root)
                            controller.viewWillAppear(false)
                            let state = KeyboardState.shared
                            state.refreshHostInputTraits(from: controller.proxy)
                            let renderedStatus: DictationStatus = page == "listening" ? .recording
                                : page == "processing" ? .processing : page == "failure" ? .failed : .idle
                            state.dictationStatus = renderedStatus
                            state.statusMessage = page == "failure" ? "Open sAiity to prepare dictation." : nil
                            let mode: KeyboardAreaMode = page == "letters" ? .letters
                                : page.hasPrefix("symbols") ? .panel : page == "emoji" ? .emoji
                                : page == "numbers" || page == "decimal" || page == "phone" ? .numberPad
                                : page == "listening" ? .recording : .keys
                            state.presentArea(mode)
                            controller.view.setNeedsLayout()
                            controller.view.layoutIfNeeded()
                            controller.viewDidLayoutSubviews()
                            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                            if !landscape && !TOPBAR,
                               let height = controller.inputView?.constraints.first(where: {
                                   $0.firstAttribute == .height && $0.secondItem == nil
                               })?.constant {
                                let resolved = CGSize(width: size.width, height: height)
                                window.frame.size = CGSize(width: size.width, height: height + 80)
                                root.view.frame = window.bounds
                                controller.view.frame = CGRect(x: 0, y: 80, width: resolved.width, height: resolved.height)
                                controller.inputView?.frame.size = resolved
                                controller.viewDidLayoutSubviews()
                            }
                            if page == "symbols2" {
                                func selectSymbols(_ view: UIView) {
                                    if let grid = view as? KeyGridView { grid.setPage(KeyGridPageFactory.symbols(.symbolsPunctuation)) }
                                    view.subviews.forEach(selectSymbols)
                                }
                                selectSymbols(controller.view)
                            }
                            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                            // Cached controller timers can restore persisted idle
                            // during settling. Reapply the inert visual state
                            // immediately before capturing the native face.
                            state.dictationStatus = renderedStatus
                            controller.viewDidLayoutSubviews()
                            controller.view.layoutIfNeeded()
                            let name = "\(page)-\(Int(width))-\(landscape ? "landscape" : "portrait")-\(glass ? "glass" : "solid")-\(dark ? "dark" : "light")"
                            let pixels = UIGraphicsImageRenderer(size: window.bounds.size).image { context in
                                root.view.layer.render(in: context.cgContext)
                            }
                            try pixels.pngData()?.write(to: URL(fileURLWithPath: "OUTPUT/\(name).png"))
                            var frames: [String: String] = [:]
                            func inspect(_ view: UIView) {
                                guard !view.isHidden else { return }
                                if let grid = view as? KeyGridView {
                                    for key in grid.layout.placed {
                                        frames[key.key.id + ".plate"] = NSCoder.string(for: grid.convert(key.plate, to: controller.view))
                                        frames[key.key.id + ".target"] = NSCoder.string(for: grid.convert(key.target, to: controller.view))
                                    }
                                }
                                if view is UIControl, let id = view.accessibilityIdentifier {
                                    frames[id] = NSCoder.string(for: view.convert(view.bounds, to: controller.view))
                                }
                                view.subviews.forEach(inspect)
                            }
                            inspect(controller.view)
                            geometry[name] = frames
                            controller.viewWillDisappear(false)
                            controller.viewDidDisappear(false)
                            controller.willMove(toParent: nil)
                            controller.view.removeFromSuperview()
                            controller.removeFromParent()
                            window.isHidden = true
                            print("Rendered \(name)")
                        }
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "OUTPUT/geometry.json"))
    }
}
"""#.replacingOccurrences(of: "OUTPUT", with: output).replacingOccurrences(of: "LARGE", with: String(large))
        .replacingOccurrences(of: "EMOJIONLY", with: String(emojiOnly))
        .replacingOccurrences(of: "INSET", with: String(inset))
        .replacingOccurrences(of: "TOPBAR", with: String(topBar))
        .replacingOccurrences(of: "KEYPAD", with: String(keypadOnly))
        .replacingOccurrences(of: "SHORTCUTS", with: String(shortcutsOnly))
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-keyboard-fixtures-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("render")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Native keyboard fixture command failed") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-I", products, "-I", derived + "/Build/Intermediates.noindex/Dictus.build/Debug-iphonesimulator/DictusKeyboard.build/Objects-normal/arm64",
             "-I", "DictusKeyboard/Vendored/AOSPTrie/bridge", source.path,
             extensionPath + "/DictusKeyboard.debug.dylib", "-Xlinker", "-rpath", "-Xlinker", extensionPath, "-o", binary.path])
_ = try run(["simctl", "spawn", simulator, binary.path])
