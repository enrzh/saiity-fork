// Run after a simulator build: swift scripts/test-key-grid-typing.swift <udid> <derived-data> [--baseline]
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fatalError("Usage: test-key-grid-typing.swift <simulator-udid> <derived-data> [--baseline]")
}
let udid = CommandLine.arguments[1]
let derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let extensionPath = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let baseline = CommandLine.arguments.contains("--baseline")
let program = """
import UIKit
import SwiftUI
import ObjectiveC
import DictusCore
@testable import DictusKeyboard

var capturedImpacts: [Double] = []
var capturedSelections = 0
extension UISelectionFeedbackGenerator {
    @objc dynamic func captureSelectionTick() { capturedSelections += 1 }
}
extension UIImpactFeedbackGenerator {
    @objc dynamic func capturePresetImpact(_ intensity: CGFloat) {
        capturedImpacts.append(Double(intensity))
    }
    @objc dynamic func captureSnappyImpact() {
        capturedImpacts.append(1)
    }
}

final class Finger: UITouch {
    var point = CGPoint.zero
    var time: TimeInterval = 0
    override func location(in view: UIView?) -> CGPoint { point }
    override var timestamp: TimeInterval { time }
}
final class Recorder: KeyGridViewDelegate {
    var text = ""
    func keyGrid(_ view: KeyGridView, perform action: KeyAction, key: KeyGridKey) {
        if case .insert(let value) = action { text += value }
    }
    func keyGridDidBeginRepeat(_ view: KeyGridView, key: KeyGridKey) {}
    func keyGridDidEndRepeat(_ view: KeyGridView) {}
}
let defaults = AppGroup.defaults
let saved = defaults.object(forKey: SharedKeys.keyPopupMode)
defer {
    if let saved { defaults.set(saved, forKey: SharedKeys.keyPopupMode) }
    else { defaults.removeObject(forKey: SharedKeys.keyPopupMode) }
}
defaults.set(KeyPopupMode.off.rawValue, forKey: SharedKeys.keyPopupMode)
let grid = KeyGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 175))
let recorder = Recorder()
grid.delegate = recorder
grid.setPage(KeyGridPageFactory.letters())
grid.layoutIfNeeded()
func finger(_ value: String, time: TimeInterval = 0) -> Finger {
    let key = grid.layout.placed.first { $0.key.resolvedLabel.lowercased() == value }!
    let touch = Finger()
    touch.point = CGPoint(x: key.plate.midX, y: key.plate.midY)
    touch.time = time
    return touch
}
let a = finger("a", time: 1), s = finger("s", time: 2)
grid.touchesBegan([a], with: nil)
grid.touchesBegan([s], with: nil)
grid.touchesEnded([s], with: nil)
grid.touchesEnded([a], with: nil)
print("OVERLAP: \\(recorder.text) (expected as)")
if !\(baseline) {
    precondition(recorder.text == "as", "Overlapping accent/plain presses reversed typing order")
    recorder.text = ""
    grid.touchesBegan([s, a], with: nil)
    grid.touchesEnded([a, s], with: nil)
    precondition(recorder.text == "as", "A simultaneous touch set lost timestamp order")
    recorder.text = ""
    grid.touchesBegan([a], with: nil)
    grid.commitPendingCharacter() // The shared proxy route settles before Space or Period.
    grid.commitPendingCharacter()
    grid.touchesEnded([a], with: nil)
    precondition(recorder.text == "a", "A bottom-bar action must settle the letter exactly once")
    recorder.text = ""
    let shift = Finger()
    let shiftKey = grid.layout.placed.first { if case .shift = $0.key.action { return true }; return false }!
    shift.point = CGPoint(x: shiftKey.plate.midX, y: shiftKey.plate.midY)
    grid.touchesBegan([shift], with: nil)
    grid.touchesEnded([shift], with: nil)
    grid.touchesBegan([a], with: nil)
    grid.touchesBegan([s], with: nil)
    grid.touchesEnded([a, s], with: nil)
    precondition(recorder.text == "As", "One-shot Shift must follow press order")
    recorder.text = ""
    grid.touchesBegan([a], with: nil)
    grid.touchesCancelled([a], with: nil)
    precondition(recorder.text.isEmpty, "A cancelled pending letter must not insert")
    grid.touchesBegan([a], with: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.holdRecognitionDuration + 0.05))
    precondition(!grid.subviews.isEmpty, "Accent hold must still expose its popup")
    grid.touchesEnded([a], with: nil)
    precondition(recorder.text == "a", "Accent hold must commit exactly one letter")
}

defaults.set(KeyPopupMode.popup.rawValue, forKey: SharedKeys.keyPopupMode)
var samples: [Double] = []
var hosts = Set<ObjectIdentifier>()
for _ in 0..<100 {
    let started = ProcessInfo.processInfo.systemUptime
    grid.touchesBegan([s], with: nil)
    if let preview = grid.subviews.last { hosts.insert(ObjectIdentifier(preview)) }
    grid.touchesEnded([s], with: nil)
    samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
}
samples.sort()
print("MEASURE: preview press/release, 100 samples, median=\\(samples[50]) ms p95=\\(samples[95]) ms hosts=\\(hosts.count)")
if !\(baseline) { precondition(hosts.count == 1, "Each letter rebuilt its preview view") }
if !\(baseline) {
    let surface = KeyboardSurfaceView(frame: CGRect(x: 0, y: 0, width: 402, height: 269))
    let layout = VoiceOnlyKeyboardPolicy.layout(for: 402, surfaceHeight: 269, topAccessoryHeight: 36)
    let savedGlass = defaults.object(forKey: SharedKeys.liquidGlassEnabled)
    let savedInset = defaults.object(forKey: SharedKeys.keyboardInsetEnabled)
    defer {
        if let savedGlass { defaults.set(savedGlass, forKey: SharedKeys.liquidGlassEnabled) }
        else { defaults.removeObject(forKey: SharedKeys.liquidGlassEnabled) }
        if let savedInset { defaults.set(savedInset, forKey: SharedKeys.keyboardInsetEnabled) }
        else { defaults.removeObject(forKey: SharedKeys.keyboardInsetEnabled) }
    }
    for glass in [true, false] {
        defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
        surface.show(.emoji, layout: layout, inputHeight: 269, fieldKeys: .standard)
        surface.layoutIfNeeded()
        let inset = KeyboardNativeControlFace()
        defaults.set(true, forKey: SharedKeys.keyboardInsetEnabled)
        inset.configureInset(layout, inputHeight: 269)
        let collection = surface.emoji.subviews.compactMap { $0 as? UICollectionView }.first!
        precondition(inset.frame.contains(surface.bottomBar.frame), "Emoji inset excludes bottom bar")
        precondition(!inset.isUserInteractionEnabled, "Shared inset steals touches")
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad, .keys] {
            surface.show(mode, layout: layout, inputHeight: 269, fieldKeys: .standard)
            inset.configureInset(layout, inputHeight: 269)
            precondition(!inset.isHidden && inset.frame == layout.surfaceFrame)
            if [.letters, .panel, .emoji].contains(mode) {
                let bar = surface.bottomBar
                precondition(bar.frame.height == 53, "Shared bottom-row hit lane is still compact")
                for control in [bar.firstControl, bar.secondControl, bar.returnControl, bar.spaceControl] as [UIControl] {
                    precondition(control.frame.height == 53 && bar.bounds.contains(control.frame))
                    control.keyboardFace.layoutIfNeeded()
                    let plate = control.keyboardFace.subviews.compactMap { $0 as? UIVisualEffectView }.first!
                    precondition(plate.frame.height == 45, "Bottom face must match character height")
                }
            }
        }
        defaults.set(false, forKey: SharedKeys.keyboardInsetEnabled)
        inset.configureInset(layout, inputHeight: 269)
        precondition(inset.isHidden, "Inset preference must apply to either material")
        surface.show(.letters, layout: layout, inputHeight: 269, fieldKeys: .standard)
        surface.period.layoutIfNeeded()
        let periodControl = surface.period.subviews.compactMap { $0 as? KeyboardKeyTouchControl }.first!
        let periodFinger = Finger()
        periodFinger.point = CGPoint(x: periodControl.bounds.midX, y: periodControl.bounds.midY)
        let barChildren = surface.bottomBar.subviews.count
        periodControl.touchesBegan([periodFinger], with: nil)
        precondition(surface.bottomBar.subviews.count == barChildren + 1, "Period must present its shared preview")
        surface.period.frame.origin.x += 20
        surface.period.setNeedsLayout()
        surface.period.layoutIfNeeded()
        precondition(surface.bottomBar.subviews.count == barChildren, "Moving Period must cancel its stale preview")
        surface.show(.emoji, layout: layout, inputHeight: 269, fieldKeys: .standard)
        precondition(abs(surface.emojiCategory.frame.midX - surface.bottomBar.spaceControl.convert(surface.bottomBar.spaceControl.bounds, to: surface).midX) < 0.01,
                     "Category must centre above the actual emoji Space key")
        precondition(collection.decelerationRate == .normal && !collection.isPagingEnabled,
                     "Native emoji momentum was disabled")
        let blank = CGPoint(x: surface.emoji.frame.midX, y: surface.emoji.frame.minY + 1)
        precondition(surface.hitTest(blank, with: nil) === collection,
                     "Blank emoji space must reach its scroll view in both materials")
        precondition(surface.emoji.frame.maxY <= surface.emojiCategory.frame.minY - surface.emojiCategory.hitExpansion,
                     "Category hit expansion covers the last emoji row")
    }

    for glass in [true, false] {
        defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
        for mode in [KeyPopupMode.popup, .popout] {
            defaults.set(mode.rawValue, forKey: SharedKeys.keyPopupMode)
            for keyWidth in [34.0, 82.0] {
                let size = CGSize(width: 852, height: 134)
                let source = CGRect(x: 720, y: 10, width: keyWidth, height: 30)
                let frame = KeyPressPreviewHost.frame(for: source, in: size)
                precondition(CGRect(origin: .zero, size: size).contains(frame), "Landscape preview escapes its host")
                let preview = KeyPreviewSession(text: "a", sourceFrame: source, popupFrame: frame)
                let host = UIHostingController(rootView: KeyPressPreviewHost(session: .constant(preview)))
                let container = UIView(frame: CGRect(origin: .zero, size: size))
                host.view.frame = container.bounds
                attachKeyboardVisualController(host, from: container)
                precondition(host.safeAreaRegions.isEmpty, "Landscape safe area shifts the preview")
                host.view.layoutIfNeeded()
                detachKeyboardVisualController(host)
            }
            grid.frame.size = CGSize(width: 402, height: 175)
            grid.layoutIfNeeded()
            let held = finger("a")
            recorder.text = ""
            grid.touchesBegan([held], with: nil)
            grid.frame.size = CGSize(width: 852, height: 134)
            grid.layoutIfNeeded()
            grid.touchesEnded([held], with: nil)
            precondition(recorder.text.isEmpty, "Rotating a held key must cancel its old finger")
            let rotated = finger("s")
            grid.touchesBegan([rotated], with: nil)
            grid.touchesEnded([rotated], with: nil)
            precondition(recorder.text == "s", "Typing must resume after rotation")
        }
    }
    grid.frame.size = CGSize(width: 402, height: 175)
    grid.layoutIfNeeded()
    defaults.set(KeyPopupMode.popup.rawValue, forKey: SharedKeys.keyPopupMode)
    print("PASS: shared inset toggle, category/Space centre, both landscape preview styles and rotation cancellation")

    // Observe the actual UIKit generator calls without needing a simulator motor.
    let impact = class_getInstanceMethod(UIImpactFeedbackGenerator.self,
        #selector(UIImpactFeedbackGenerator.impactOccurred(intensity:)))!
    let capture = class_getInstanceMethod(UIImpactFeedbackGenerator.self,
        #selector(UIImpactFeedbackGenerator.capturePresetImpact(_:)))!
    let fullImpact = class_getInstanceMethod(UIImpactFeedbackGenerator.self,
        NSSelectorFromString("impactOccurred"))!
    let fullCapture = class_getInstanceMethod(UIImpactFeedbackGenerator.self,
        #selector(UIImpactFeedbackGenerator.captureSnappyImpact))!
    method_exchangeImplementations(impact, capture)
    method_exchangeImplementations(fullImpact, fullCapture)
    let savedHaptics = defaults.object(forKey: SharedKeys.hapticIntensity)
    let savedEnabled = defaults.object(forKey: SharedKeys.hapticsEnabled)
    defer {
        method_exchangeImplementations(impact, capture)
        method_exchangeImplementations(fullImpact, fullCapture)
        for (key, value) in [(SharedKeys.hapticIntensity, savedHaptics), (SharedKeys.hapticsEnabled, savedEnabled)] {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        HapticFeedback.refreshEnabledState()
    }
    let delete = KeyboardDeleteRepeatControl(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    for preset in HapticIntensity.allCases {
        preset.persist()
        HapticFeedback.refreshEnabledState()
        capturedImpacts.removeAll()
        grid.touchesBegan([s], with: nil)
        grid.touchesEnded([s], with: nil)
        precondition(delete.accessibilityActivate())
        switch preset {
        case .off: precondition(capturedImpacts.isEmpty, "Off still vibrates")
        case .default, .snappy:
            let expected = preset == .snappy ? 1.0 : 0.42
            precondition(capturedImpacts.count == 2 && capturedImpacts.allSatisfy { abs($0 - expected) < 0.0001 },
                         "Letters and Emoji Delete disagree with the selected haptic preset")
        }
    }
    print("PASS: UIKit haptic delivery, Off/Default/Snappy, letter and Emoji Delete use the same impulse")

    let savedSpeed = defaults.object(forKey: SharedKeys.keyboardHoldSpeed)
    let savedVariants = defaults.object(forKey: SharedKeys.disabledKeyVariants)
    defer {
        for (key, value) in [(SharedKeys.keyboardHoldSpeed, savedSpeed), (SharedKeys.disabledKeyVariants, savedVariants)] {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        KeyboardVariantPreferences.reload()
    }
    let host = NextKeyboardHost()
    host.show(.letters)
    let original = host.gridView.page!.rows.flatMap { $0 }.first { $0.resolvedLabel.lowercased() == "a" }!
    let alternate = original.variants.last!
    KeyboardVariantPreferences.setEnabled(false, option: alternate, key: "a", kind: .letter)
    host.refreshKeyLayout()
    let filtered = host.gridView.page!.rows.flatMap { $0 }.first { $0.resolvedLabel.lowercased() == "a" }!
    precondition(!filtered.variants.contains(alternate), "Mounted keyboard retained a disabled alternate")
    KeyboardVariantPreferences.setEnabled(true, option: alternate, key: "a", kind: .letter)
    host.refreshKeyLayout()
    precondition(host.gridView.page!.rows.flatMap { $0 }.first { $0.resolvedLabel.lowercased() == "a" }!.variants.contains(alternate),
                 "Mounted keyboard did not restore an alternate")
    defaults.set(KeyboardHoldSpeed.snappy.rawValue, forKey: SharedKeys.keyboardHoldSpeed)
    var deletions = 0
    delete.onDelete = { deletions += 1 }
    delete.touchesBegan([s], with: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.repeatDelay + 0.05))
    precondition(deletions >= 2, "Delete did not repeat at the selected speed")
    delete.touchesCancelled([s], with: nil)
    let stoppedAt = deletions
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.repeatInterval * 2))
    precondition(deletions == stoppedAt, "Cancelled Delete kept deleting")
    capturedImpacts.removeAll()
    deletions = 0
    delete.touchesBegan([s], with: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.repeatDelay + KeyboardDeletion.repeatInterval * 2.5))
    delete.touchesEnded([s], with: nil)
    precondition(deletions >= 3 && capturedImpacts.count == deletions,
                 "Every held Delete tick must emit the selected vibration")

    let selection = class_getInstanceMethod(UISelectionFeedbackGenerator.self,
        #selector(UISelectionFeedbackGenerator.selectionChanged))!
    let selectionCapture = class_getInstanceMethod(UISelectionFeedbackGenerator.self,
        #selector(UISelectionFeedbackGenerator.captureSelectionTick))!
    method_exchangeImplementations(selection, selectionCapture)
    capturedSelections = 0
    for _ in 0..<5 { HapticFeedback.cursorMoved() }
    method_exchangeImplementations(selection, selectionCapture)
    precondition(capturedSelections == 5, "Rapid character moves lost haptic ticks")

    let space = SpaceTrackingButton.TrackingControl(frame: CGRect(x: 0, y: 0, width: 150, height: 44))
    var spaces = 0
    space.onTap = { spaces += 1 }
    capturedImpacts.removeAll()
    precondition(space.beginTracking(s, with: nil))
    precondition(spaces == 0 && capturedImpacts.count == 1, "Space must acknowledge the press before committing on release")
    space.endTracking(s, with: nil)
    precondition(spaces == 1 && capturedImpacts.count == 1, "Space release must commit once without a second vibration")
    _ = space.beginTracking(s, with: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.cursorHoldDuration + 0.05))
    space.endTracking(s, with: nil)
    precondition(spaces == 1, "Cursor hold inserted an unwanted space")
    var spaceSamples: [Double] = []
    for _ in 0..<100 {
        let began = ProcessInfo.processInfo.systemUptime
        _ = space.beginTracking(s, with: nil)
        space.endTracking(s, with: nil)
        spaceSamples.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
    }
    spaceSamples.sort()
    print("MEASURE: Space press/release, median=\\(spaceSamples[50]) ms p95=\\(spaceSamples[95]) ms")
    print("PASS: repeated Delete haptics, each cursor tick, immediate Space feedback and cursor hold without insertion")
    print("PASS: live alternate reload, reserved category lane, held Delete and cancellation")

    for speed in KeyboardHoldSpeed.allCases {
        let hold = KeyboardHoldSession()
        var fired = 0
        hold.begin(after: speed.duration) { fired += 1 }
        RunLoop.current.run(until: Date().addingTimeInterval(speed.duration * 0.7))
        precondition(fired == 0, "Hold fired before its selected speed")
        RunLoop.current.run(until: Date().addingTimeInterval(speed.duration * 0.4))
        precondition(fired == 1, "Hold did not recognize once at its selected speed")
        hold.begin(after: 0.01) { fired += 1 }
        hold.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(fired == 1, "Cancelled hold fired later")
    }
    let keypad = KeyGridPageFactory.numberPad(style: .decimal)
    precondition(keypad.rows.last?.first?.resolvedLabel == Locale.current.decimalSeparator,
                 "Decimal host got the digit-only pad")
    let phoneZero = KeyGridPageFactory.numberPad(style: .phone).rows.last![1]
    precondition(phoneZero.variants.contains("+"), "Phone host cannot hold zero for plus")
    let categories = EmojiCategoryControl(frame: CGRect(x: 0, y: 0, width: 300, height: 22))
    categories.sectionCount = 10
    var selectedCategory = -1
    categories.onIndexChanged = { selectedCategory = $0 }
    let categoryTouch = Finger()
    categoryTouch.point = CGPoint(x: 299, y: 11)
    precondition(categories.beginTracking(categoryTouch, with: nil))
    categories.endTracking(categoryTouch, with: nil)
    precondition(selectedCategory == 9, "Last visible category is unreachable")
    categoryTouch.point.x = 1
    precondition(categories.beginTracking(categoryTouch, with: nil))
    categories.endTracking(categoryTouch, with: nil)
    precondition(selectedCategory == 0, "First visible category is unreachable")
    for width in [205.0, 242, 500] {
        categories.frame.size.width = width
        let slot = EmojiCategoryBarMetrics.slotWidth(trackWidth: width, sectionCount: 10)
        for index in 0..<10 {
            categoryTouch.point.x = EmojiCategoryBarMetrics.railInset + (CGFloat(index) + 0.5) * slot
            _ = categories.beginTracking(categoryTouch, with: nil)
            categories.endTracking(categoryTouch, with: nil)
            precondition(selectedCategory == index, "Category touch disagrees with its drawn icon cell")
        }
        _ = categories.beginTracking(categoryTouch, with: nil)
        categoryTouch.point.x = -20
        _ = categories.continueTracking(categoryTouch, with: nil)
        precondition(selectedCategory == 0)
        categoryTouch.point.x = width + 20
        _ = categories.continueTracking(categoryTouch, with: nil)
        precondition(selectedCategory == 9)
        categories.endTracking(categoryTouch, with: nil)
        categories.accessibilityDecrement()
        precondition(selectedCategory == 8)
    }
    print("PASS: 45pt bottom faces on every shared page, all category icon taps, drags and accessibility")
    func namedControl(_ id: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        return view.subviews.lazy.compactMap { namedControl(id, in: $0) }.first
    }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
    controller.inputView?.frame = controller.view.frame
    controller.viewWillAppear(false)
    let savedArea = KeyboardState.shared.areaMode
    defer {
        KeyboardState.shared.presentArea(savedArea)
        controller.viewWillDisappear(false)
    }
    for glass in [true, false] {
        defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad] {
            KeyboardState.shared.presentArea(mode)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.viewDidLayoutSubviews()
            let toggle = namedControl("dictation-service-toggle", in: controller.view)!
            let board = namedControl("return-to-dictation-board", in: controller.view)!
            precondition(!toggle.isHidden && toggle.isUserInteractionEnabled, "Service control must stay reachable on every page")
            precondition(toggle.frame.midY == board.frame.midY && toggle.frame.maxX < board.frame.minX,
                         "Service control must sit beside the dictation board control")
            let point = CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY)
            precondition(toggle.hitTest(point, with: nil) != nil, "Visible power control lost its native hit target")
        }
    }
    let savedService = defaults.object(forKey: SharedKeys.serviceEnabled)
    defer {
        if let savedService { defaults.set(savedService, forKey: SharedKeys.serviceEnabled) }
        else { defaults.removeObject(forKey: SharedKeys.serviceEnabled) }
        KeyboardState.shared.refreshFromDefaults()
    }
    defaults.set(true, forKey: SharedKeys.serviceEnabled)
    KeyboardState.shared.refreshFromDefaults()
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    let service = namedControl("dictation-service-toggle", in: controller.view) as! UIButton
    precondition(service.accessibilityValue == "On")
    service.sendActions(for: .primaryActionTriggered)
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    precondition(!KeyboardDictationService.isEnabled(in: defaults), "The native action did not disable dictation")
    precondition(service.accessibilityValue == "Off", "The native control kept a stale enabled appearance")
    print("PASS: native service controls on every keyboard page in both materials")
    let face = KeyboardNativeControlFace(frame: CGRect(x: 0, y: 0, width: 156, height: 54))
    for symbol in ["mic.fill", "waveform", "ellipsis", "xmark", "power.circle.fill", "power"] {
        face.configure(text: "Dictation", symbol: symbol, visualSize: face.bounds.size, primary: true)
        face.layoutIfNeeded()
        let image = face.subviews.compactMap { $0 as? UIImageView }.first!
        precondition(image.image != nil && !image.isHidden && image.alpha == 1,
                     "Reused dictation face lost its glyph")
    }
    print("PASS: shared hold speeds/cancellation, host decimal/phone keys, category edges, retained dictation glyph")
}
print(\(baseline) ? "BASELINE recorded" : "PASS: press order, cancelled accent, hold variants, reused preview")
"""
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let input = directory.appendingPathComponent("main.swift")
let binary = directory.appendingPathComponent("typing-check")
try program.write(to: input, atomically: true, encoding: .utf8)
func run(_ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Failed: \(args.first ?? "command")")
}
let sdk = Process()
sdk.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdk.arguments = ["--sdk", "iphonesimulator", "--show-sdk-path"]
let output = Pipe()
sdk.standardOutput = output
try sdk.run()
sdk.waitUntilExit()
let sdkPath = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    .trimmingCharacters(in: .whitespacesAndNewlines)
try run(["swiftc", "-sdk", sdkPath, "-target", "arm64-apple-ios17.0-simulator",
         "-I", products, "-I", derived + "/Build/Intermediates.noindex/Dictus.build/Debug-iphonesimulator/DictusKeyboard.build/Objects-normal/arm64",
         "-I", "DictusKeyboard/Vendored/AOSPTrie/bridge", input.path,
         extensionPath + "/DictusKeyboard.debug.dylib", "-Xlinker", "-rpath", "-Xlinker", extensionPath,
         "-o", binary.path])
try run(["simctl", "spawn", udid, binary.path])
