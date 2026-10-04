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

// A real ObjC nil return exercises the SDK's misleading non-optional UUID bridge.
final class HostIdentityProbe: NSObject {
    var identifier: NSUUID?
    @objc var documentIdentifier: NSUUID? { identifier }
}
class_addProtocol(HostIdentityProbe.self, NSProtocolFromString("UITextDocumentProxy")!)
let identityProbe = HostIdentityProbe()
let identityProxy = identityProbe as! UITextDocumentProxy
precondition(HostInputTraits.documentIdentifier(for: identityProxy) == nil)
let expectedIdentity = UUID()
identityProbe.identifier = expectedIdentity as NSUUID
precondition(HostInputTraits.documentIdentifier(for: identityProxy) == expectedIdentity)
identityProbe.identifier = nil
precondition(HostInputTraits.documentIdentifier(for: identityProxy) == nil)
precondition(HostInputTraits.documentIdentifier(for: nil) == nil)
print("PASS: nullable host identity survives absent, attached and detached document contexts")

final class MenuCheckController: KeyboardViewController {
    var dismissals = 0
    override func dismissKeyboard() { dismissals += 1 }
}
let menuController = MenuCheckController()
let menu = menuController.keyboardMoreMenuItems().compactMap { $0 as? UIMenu }.last!
precondition(menu.children.map(\\.title) == ["Paste", "Output language", "Dismiss keyboard"])
let languageMenu = menu.children[1] as! UIMenu
precondition(!languageMenu.children.isEmpty)
let dismissAction = menu.children[2] as! UIAction
let menuButton = UIButton()
menuButton.addAction(dismissAction, for: .primaryActionTriggered)
menuButton.sendActions(for: .primaryActionTriggered)
precondition(menuController.dismissals == 1)
print("PASS: native More keeps Paste/output language and dismisses through its existing action")

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
func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 2, message: String) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    precondition(condition(), message)
}
final class Recorder: KeyGridViewDelegate {
    var text = ""
    func keyGrid(_ view: KeyGridView, perform action: KeyAction, key: KeyGridKey) {
        if case .insert(let value) = action { text += value }
    }
    func keyGridDidBeginRepeat(_ view: KeyGridView, key: KeyGridKey) {}
    func keyGridDidEndRepeat(_ view: KeyGridView) {}
    func keyGridDidRequestDictation(_ view: KeyGridView) {}
}
let defaults = AppGroup.defaults
let appearanceKeys = [SharedKeys.keyboardIOSStyling, SharedKeys.keyboardTopBarEnabled]
let savedAppearance = appearanceKeys.map { defaults.object(forKey: $0) }
defer {
    for (key, value) in zip(appearanceKeys, savedAppearance) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
defaults.set(false, forKey: SharedKeys.keyboardIOSStyling)
defaults.set(true, forKey: SharedKeys.keyboardTopBarEnabled)
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
    precondition(grid.subviews.contains { $0.accessibilityIdentifier == "key-variant-selector" && !$0.isHidden },
                 "Accent hold must still expose its popup")
    grid.touchesEnded([a], with: nil)
    precondition(recorder.text == "a", "Accent hold must commit exactly one letter")
}

defaults.set(KeyPopupMode.popup.rawValue, forKey: SharedKeys.keyPopupMode)
var samples: [Double] = []
var hosts = Set<ObjectIdentifier>()
for _ in 0..<100 {
    let started = ProcessInfo.processInfo.systemUptime
    grid.touchesBegan([s], with: nil)
    if let preview = grid.subviews.last(where: { !($0 is UIControl) }) { hosts.insert(ObjectIdentifier(preview)) }
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
        surface.emojiDelete.keyboardFace.layoutIfNeeded()
        let deletePlate = surface.emojiDelete.keyboardFace.subviews.compactMap { $0 as? UIVisualEffectView }.first!
        precondition(deletePlate.frame.size == layout.commandKeyVisualSize
                     && surface.emojiDelete.bounds.contains(deletePlate.frame),
                     "Emoji Delete must use the enlarged command face inside its touch target")
        let inset = KeyboardNativeControlFace()
        defaults.set(true, forKey: SharedKeys.keyboardInsetEnabled)
        inset.configureInset(layout, inputHeight: 269)
        let collection = surface.emoji
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
                func visiblePlate(_ owner: UIView) -> CGRect {
                    owner.layoutIfNeeded()
                    let face = owner.subviews.compactMap { $0 as? KeyboardNativeControlFace }.first
                    face?.layoutIfNeeded()
                    let plate = (face ?? owner).subviews.compactMap { $0 as? UIVisualEffectView }.first!
                    return plate.convert(plate.bounds, to: bar)
                }
                var owners: [UIView] = [bar.firstControl, bar.secondControl, bar.spaceControl]
                if mode == .letters {
                    bar.period.layoutIfNeeded()
                    let period = bar.period.subviews.compactMap { $0 as? KeyboardKeyTouchControl }.first!
                    owners.append(period)
                }
                owners.append(bar.returnControl)
                let plates = owners.map(visiblePlate)
                for index in 1..<plates.count {
                    precondition(abs(plates[index].minX - plates[index - 1].maxX - 2) < 0.01,
                                 "Every visible bottom-row gap must be 2pt, including Period and Return")
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
        precondition(abs(surface.emoji.frame.maxY - surface.emojiCategory.frame.minY) < 0.01,
                     "Emoji list must reach immediately above the category bar")
        let lastRow = CGPoint(x: surface.emojiCategory.frame.midX, y: surface.emojiCategory.frame.minY - 5)
        precondition(surface.hitTest(lastRow, with: nil) === collection.hitTest(collection.convert(lastRow, from: surface), with: nil),
                     "Category hit expansion steals the expanded emoji row")
        let covered = CGPoint(x: surface.emojiDelete.frame.midX,
                              y: min(surface.emojiDelete.frame.maxY, surface.emoji.frame.maxY) - 1)
        precondition(surface.emoji.frame.contains(covered) && surface.emojiDelete.frame.contains(covered))
        precondition(surface.hitTest(covered, with: nil) === surface.emojiDelete,
                     "Delete must win over the emoji list behind it")
        let category = CGPoint(x: surface.emojiCategory.frame.midX, y: surface.emojiCategory.frame.midY)
        precondition(surface.hitTest(category, with: nil) === surface.emojiCategory,
                     "Expanded pager covers the visible category rail")
    }

    var commandFaces: [KeyGridView.CommandSpec] = []
    grid.onCommandFacesChanged = { commandFaces = $0 }
    for glass in [true, false] {
        defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
        for size in [CGSize(width: 320, height: 175), CGSize(width: 402, height: 175),
                     CGSize(width: 667, height: 90), CGSize(width: 852, height: 90)] {
            grid.frame.size = size
            for page in [KeyGridPageFactory.letters(),
                         KeyGridPageFactory.symbols(.symbolsNumbers),
                         KeyGridPageFactory.symbols(.symbolsPunctuation),
                         KeyGridPageFactory.numberPad(style: .digits)] {
                grid.setPage(page)
                grid.layoutIfNeeded()
                grid.refreshAppearance()
                let commands = grid.layout.placed.filter { $0.key.isCommand && $0.key.id != "pad-letters" }
                precondition(!commands.isEmpty && commandFaces.count == commands.count)
                for (command, face) in zip(commands, commandFaces) {
                    let expected = min(45, command.plate.height)
                    precondition(face.rect.height == expected && command.target.contains(face.rect),
                                 "Command sizing failed: \\(page.id) \\(size) \\(command.key.id) expected=\\(expected) face=\\(face.rect) target=\\(command.target)")
                    let envelope = CommandKeyStyle.visualPlate(for: command.plate, surfaceWidth: size.width)
                    precondition(abs(envelope.width - face.rect.width - KeyGridPlacement.keySpacing) < 0.01,
                                 "Command face must narrow without changing its reserved geometry")
                    let row = grid.layout.rows[command.row]
                    if command.column > 0 {
                        precondition(face.rect.minX - row[command.column - 1].plate.maxX >= KeyGridPlacement.keySpacing - 0.01,
                                     "Command touches its left neighbour")
                    }
                    if command.column + 1 < row.count {
                        precondition(row[command.column + 1].plate.minX - face.rect.maxX >= KeyGridPlacement.keySpacing - 0.01,
                                     "Command touches its right neighbour")
                    }
                }
            }
        }
    }
    grid.onCommandFacesChanged = nil
    grid.setPage(KeyGridPageFactory.letters())
    print("PASS: shared command heights and neighbour gaps in portrait and cramped landscape, both materials and all grid pages")

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
    waitFor({ deletions >= 2 }, message: "Delete did not repeat at the selected speed")
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
    let cursorText = UITextView()
    cursorText.text = String(repeating: "abcdefghijklmnop\\n", count: 20)
    cursorText.selectedRange = NSRange(location: 80, length: 0)
    var cursorColumn: Int?
    space.onCursorMoved = { step in
        let text = cursorText.text as NSString
        let caret = cursorText.selectedRange.location
        let start = max(0, caret - 12)
        let offset = KeyboardCursorTrackpad.visualOffset(
            beforeInput: text.substring(with: NSRange(location: start, length: caret - start)),
            afterInput: text.substring(with: NSRange(location: caret, length: min(12, text.length - caret))),
            columns: step.characters, rows: step.lines, wrap: 8, preferredColumn: &cursorColumn)
        guard let current = cursorText.selectedTextRange,
              let target = cursorText.position(from: current.start, offset: offset) else {
            preconditionFailure("Fixture cursor escaped its native text view")
        }
        cursorText.selectedTextRange = cursorText.textRange(from: target, to: target)
    }
    let cursorFinger = Finger()
    cursorFinger.point = CGPoint(x: 60, y: 20)
    let spacesBeforeCursor = spaces
    _ = space.beginTracking(cursorFinger, with: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.cursorHoldDuration + 0.05))
    for _ in 0..<40 {
        cursorFinger.point.x += KeyboardCursorTrackpad.pointsPerCharacter
        _ = space.continueTracking(cursorFinger, with: nil)
    }
    precondition(cursorText.selectedRange.location == 120,
                 "Space cursor stopped at a newline, soft wrap or rolling proxy context")
    _ = space.continueTracking(cursorFinger, with: nil)
    precondition(cursorText.selectedRange.location == 120, "A stationary held finger moved the cursor")
    for _ in 0..<40 {
        cursorFinger.point.x -= KeyboardCursorTrackpad.pointsPerCharacter
        _ = space.continueTracking(cursorFinger, with: nil)
    }
    space.endTracking(cursorFinger, with: nil)
    precondition(cursorText.selectedRange.location == 80 && spaces == spacesBeforeCursor,
                 "Cursor reversal lost travel or inserted a space")
    print("PASS: held Space crosses newlines, wraps and rolling context, reverses and leaves text untouched")
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
        guard !view.isHidden else { return nil }
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
        KeyboardState.shared.presentArea(.keys)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        let boardDelete = namedControl("board-delete", in: controller.view) as! KeyboardDeleteRepeatControl
        boardDelete.keyboardFace.layoutIfNeeded()
        let boardDeletePlate = boardDelete.keyboardFace.subviews.compactMap { $0 as? UIVisualEffectView }.first!
        precondition(boardDeletePlate.frame.height == 45 && boardDeletePlate.frame.width == boardDelete.bounds.width
                     && boardDelete.bounds.contains(boardDeletePlate.frame), "Dictation-board Delete kept its compact face")
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
            let more = namedControl("keyboard-more", in: controller.view) as! UIButton
            precondition(more.showsMenuAsPrimaryAction && more.menu != nil && !more.isHidden)
            precondition(namedControl("paste-clipboard", in: controller.view) == nil
                         && namedControl("dismiss-keyboard", in: controller.view) == nil,
                         "Minimal accessory row kept separate secondary controls")
        }
    }
    // Exercise the full window/input hierarchy, not only the isolated pager.
    let touchWindow = UIWindow(frame: controller.view.frame)
    let parent = UIViewController()
    touchWindow.rootViewController = parent
    parent.addChild(controller)
    parent.view.addSubview(controller.view)
    controller.didMove(toParent: parent)
    touchWindow.makeKeyAndVisible()
    defer {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        touchWindow.isHidden = true
    }
    func findSurface(in view: UIView) -> KeyboardSurfaceView? {
        if let surface = view as? KeyboardSurfaceView { return surface }
        return view.subviews.lazy.compactMap { findSurface(in: $0) }.first
    }
    let liveSurface = findSurface(in: controller.view)!
    let savedRecents = defaults.object(forKey: "recentEmojis")
    defer {
        if let savedRecents { defaults.set(savedRecents, forKey: "recentEmojis") }
        else { defaults.removeObject(forKey: "recentEmojis") }
    }
    for glass in [true, false] {
        defaults.set(glass, forKey: SharedKeys.liquidGlassEnabled)
        for inset in [true, false, true, false] {
            defaults.set(inset, forKey: SharedKeys.keyboardInsetEnabled)
            for size in [CGSize(width: 320, height: 300), CGSize(width: 402, height: 300),
                         CGSize(width: 667, height: 190), CGSize(width: 852, height: 190)] {
                touchWindow.frame.size = size
                parent.view.frame = touchWindow.bounds
                controller.view.frame = touchWindow.bounds
                controller.inputView?.frame = touchWindow.bounds
                KeyboardState.shared.presentArea(.letters)
                KeyboardState.shared.presentArea(.emoji)
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                controller.viewDidLayoutSubviews()
                liveSurface.refreshAppearance()
                liveSurface.layoutIfNeeded()
                liveSurface.emoji.layoutIfNeeded()
                let pager = liveSurface.emoji
                defaults.set([String](), forKey: "recentEmojis")
                pager.selectCategory(at: 0)
                pager.layoutIfNeeded()
                for localPoint in [CGPoint(x: pager.bounds.midX, y: pager.bounds.minY + 1),
                                   CGPoint(x: pager.bounds.midX, y: pager.bounds.midY),
                                   CGPoint(x: pager.bounds.minX + 1, y: pager.bounds.midY),
                                   CGPoint(x: pager.bounds.maxX - 1, y: pager.bounds.midY)] {
                    let point = pager.convert(localPoint, to: touchWindow)
                    precondition(touchWindow.hitTest(point, with: nil) === pager,
                                 "Window lost blank Emoji touch: glass=\\(glass) inset=\\(inset) size=\\(size) point=\\(point)")
                }
                precondition(pager.isScrollEnabled && pager.panGestureRecognizer.isEnabled
                             && pager.panGestureRecognizer.view === pager)
                let blankFinger = Finger()
                blankFinger.point = CGPoint(x: pager.bounds.midX, y: pager.bounds.midY)
                precondition(pager.gestureRecognizer(pager.panGestureRecognizer, shouldReceive: blankFinger),
                             "Empty Recents must admit the native pan")
                pager.selectCategory(at: 1)
                pager.layoutIfNeeded()
                func emojiButton(in view: UIView) -> UIControl? {
                    if let button = view as? UIButton, button.accessibilityLabel != nil { return button }
                    return view.subviews.lazy.compactMap { emojiButton(in: $0) }.first
                }
                let button = pager.visibleCells.lazy.compactMap { emojiButton(in: $0) }.first!
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: touchWindow)
                precondition(touchWindow.hitTest(point, with: nil) === button,
                             "Native emoji taps must survive inset changes")
                var insertedEmoji: String?
                let originalInsert = pager.onInsert
                pager.onInsert = { insertedEmoji = $0 }
                // The headless fixture has no UIApplication action dispatcher.
                precondition(button.accessibilityActivate())
                pager.onInsert = originalInsert
                precondition(insertedEmoji?.isEmpty == false, "Emoji insertion handler was lost")
            }
        }
    }
    controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
    controller.inputView?.frame = controller.view.frame
    print("PASS: window-level Emoji taps, blank/empty Recents pan routing and inset transitions in both materials and orientations")
    for native in [false, true] {
        defaults.set(native, forKey: SharedKeys.keyboardIOSStyling)
        defaults.set(false, forKey: SharedKeys.keyboardTopBarEnabled)
        defaults.set((native ? KeyboardHoldSpeed.default : .snappy).rawValue, forKey: SharedKeys.keyboardHoldSpeed)
        touchWindow.frame.size = CGSize(width: 402, height: 300)
        parent.view.frame = touchWindow.bounds
        controller.view.frame = touchWindow.bounds
        controller.inputView?.frame = touchWindow.bounds
        for style in [HostFieldPolicy.NumberPadStyle.digits, .decimal, .phone] {
            KeyboardState.shared.presentArea(.numberPad)
            controller.viewDidLayoutSubviews()
            let keypad = (controller.inputView as! KeyboardInputView).nativeTouchOwners.compactMap { $0 as? KeyGridView }.first!
            keypad.setPage(KeyGridPageFactory.numberPad(style: style))
            keypad.layoutIfNeeded()
            keypad.refreshAppearance()
            if style == .digits {
                let letters = namedControl("pad-letter-switch", in: keypad) as! KeyboardKeyTouchControl
                let held = Finger()
                held.point = CGPoint(x: letters.bounds.midX, y: letters.bounds.midY)
                letters.touchesBegan([held], with: nil)
                precondition(KeyboardState.shared.areaMode == .numberPad, "Numeric ABC switched before its hold could resolve")
                letters.touchesEnded([held], with: nil)
                precondition(KeyboardState.shared.areaMode == .letters, "Numeric ABC tap did not open letters")
                KeyboardState.shared.presentArea(.numberPad)
                controller.viewDidLayoutSubviews()
                letters.touchesBegan([held], with: nil)
                waitFor({ KeyboardState.shared.areaMode == .keys }, message: "Numeric ABC hold did not open dictation")
                letters.touchesEnded([held], with: nil)
                precondition(KeyboardState.shared.areaMode == .keys, "Numeric ABC hold release also opened letters")
                KeyboardState.shared.presentArea(.numberPad)
                controller.viewDidLayoutSubviews()
            }
            let shortcut = namedControl("pad-dictation-board", in: keypad) as! KeyboardKeyTouchControl
            let point = shortcut.convert(CGPoint(x: shortcut.bounds.midX, y: shortcut.bounds.midY), to: touchWindow)
            precondition(touchWindow.hitTest(point, with: nil) === shortcut,
                         "Hidden bar left a numeric host without a dictation route")
            let delete = keypad.layout.placed.first { $0.key.id == "pad-delete" }!
            let deletePoint = keypad.convert(CGPoint(x: delete.plate.midX, y: delete.plate.midY), to: touchWindow)
            precondition(touchWindow.hitTest(deletePoint, with: nil) === keypad,
                         "Numeric voice shortcut intercepted Delete")
            precondition(shortcut.accessibilityActivate())
            precondition(KeyboardState.shared.areaMode == .keys, "Numeric voice action did not open the board")
        }
        for width: CGFloat in [667, 852] {
            touchWindow.frame.size = CGSize(width: width, height: 158)
            parent.view.frame = touchWindow.bounds
            controller.view.frame = touchWindow.bounds
            controller.inputView?.frame = touchWindow.bounds
            for mode in [KeyboardAreaMode.letters, .panel, .emoji, .keys] {
                KeyboardState.shared.presentArea(mode)
                controller.viewDidLayoutSubviews()
                if mode == .keys {
                    precondition(namedControl("number-layer", in: controller.view)?.bounds.isEmpty == false,
                                 "Compact landscape lost the board return shortcut")
                } else {
                    for owner in [liveSurface.bottomBar.firstControl, liveSurface.bottomBar.secondControl,
                                  liveSurface.bottomBar.returnControl, liveSurface.bottomBar.spaceControl] as [UIControl] {
                        precondition(!owner.bounds.isEmpty, "Compact landscape lost a bottom key")
                        let point = owner.convert(CGPoint(x: owner.bounds.midX, y: owner.bounds.midY), to: touchWindow)
                        precondition(touchWindow.hitTest(point, with: nil) === owner,
                                     "Compact landscape bottom key lost its native touch recipient")
                    }
                }
            }
        }
        for mode in [KeyboardAreaMode.letters, .panel, .emoji] {
            KeyboardState.shared.presentArea(mode)
            controller.viewDidLayoutSubviews()
            waitFor({ controller.inputView!.constraints.contains {
                $0.firstAttribute == .height && $0.secondItem == nil
            } }, message: "Deferred keyboard height constraint was not installed")
            let requestedHeight = controller.inputView!.constraints.first {
                $0.firstAttribute == .height && $0.secondItem == nil
            }!.constant
            touchWindow.frame.size = CGSize(width: 402, height: requestedHeight)
            parent.view.frame = touchWindow.bounds
            controller.view.frame = touchWindow.bounds
            controller.inputView?.frame = touchWindow.bounds
            controller.viewDidLayoutSubviews()
            liveSurface.refreshAppearance()
            precondition(namedControl("dictation-service-toggle", in: controller.view) == nil
                && namedControl("return-to-dictation-board", in: controller.view) == nil
                && namedControl("keyboard-more", in: controller.view) == nil,
                "Hidden top bar left a visible or active accessory")
            precondition(liveSurface.emoji.frame.minY < 10, "Hidden bar kept its reserved empty strip")
            if mode == .letters {
                let grid = (controller.inputView as! KeyboardInputView).nativeTouchOwners.compactMap { $0 as? KeyGridView }.first!
                precondition(grid.layout.rows.allSatisfy { $0.allSatisfy { $0.plate.height == 45 } },
                             "Minimal keyboard shrank the character plates")
            }
            let key = liveSurface.bottomBar.firstControl
            precondition(key.holdDuration == KeyboardDeletion.holdRecognitionDuration,
                         "Cached page key retained its previous hold-speed setting")
            let tap = Finger()
            tap.point = CGPoint(x: key.bounds.midX, y: key.bounds.midY)
            key.touchesBegan([tap], with: nil)
            precondition(KeyboardState.shared.areaMode == mode, "Layer switched before tap/hold was resolved")
            key.touchesEnded([tap], with: nil)
            precondition(KeyboardState.shared.areaMode == (mode == .panel ? .letters : .panel))
            KeyboardState.shared.presentArea(mode)
            controller.viewDidLayoutSubviews()
            key.touchesBegan([tap], with: nil)
            waitFor({ KeyboardState.shared.areaMode == .keys }, message: "Hold failed to open dictation")
            key.touchesEnded([tap], with: nil)
            precondition(KeyboardState.shared.areaMode == .keys, "Hold release also performed the tap")
            let boardKey = namedControl("number-layer", in: controller.view) as! KeyboardKeyTouchControl
            precondition(boardKey.holdDuration == KeyboardDeletion.holdRecognitionDuration,
                         "Cached board key retained its previous hold-speed setting")
            tap.point = CGPoint(x: boardKey.bounds.midX, y: boardKey.bounds.midY)
            boardKey.touchesBegan([tap], with: nil)
            waitFor({ KeyboardState.shared.areaMode == .letters }, message: "Board hold failed to return to letters")
            boardKey.touchesEnded([tap], with: nil)
            precondition(KeyboardState.shared.areaMode == .letters, "Board hold release switched to symbols")
            key.touchesBegan([tap], with: nil)
            key.touchesCancelled([tap], with: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.holdRecognitionDuration + 0.03))
            precondition(KeyboardState.shared.areaMode == .letters, "Cancelled hold fired later")
            tap.point = CGPoint(x: key.bounds.midX, y: key.bounds.midY)
            key.touchesBegan([tap], with: nil)
            tap.point.x = -1
            key.touchesMoved([tap], with: nil)
            key.touchesEnded([tap], with: nil)
            precondition(KeyboardState.shared.areaMode == .letters, "Moving outside the page key performed a tap")
            tap.point = CGPoint(x: key.bounds.midX, y: key.bounds.midY)
            key.touchesBegan([tap], with: nil)
            let originalFrame = key.frame
            key.frame.origin.x += 8
            RunLoop.current.run(until: Date().addingTimeInterval(KeyboardDeletion.holdRecognitionDuration + 0.03))
            key.touchesEnded([tap], with: nil)
            key.frame = originalFrame
            precondition(KeyboardState.shared.areaMode == .letters, "Resizing a held page key performed stale navigation")
            precondition(key.accessibilityCustomActions?.first?.name == "Open dictation board")
        }
    }
    defaults.set(false, forKey: SharedKeys.keyboardIOSStyling)
    defaults.set(true, forKey: SharedKeys.keyboardTopBarEnabled)
    KeyboardState.shared.presentArea(.keys)
    controller.viewDidLayoutSubviews()
    print("PASS: minimal/iOS styling, hidden top bar, unchanged 45pt plates, tap/hold/release/cancellation and board return")
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
    let hostKeys = HostFieldPolicy.LetterFieldKeys(leftInsert: "@", rightInsert: ".com", returnTitle: "Send")
    for mode in [KeyboardAreaMode.letters, .panel, .emoji] {
        surface.show(mode, layout: layout, inputHeight: 269, fieldKeys: hostKeys)
        let label = surface.bottomBar.returnControl.keyboardFace.subviews.compactMap { $0 as? UILabel }.first!
        precondition(label.text == "Send" && surface.bottomBar.returnControl.accessibilityLabel == "Send",
                     "Host Return must remain consistent across keyboard pages")
        precondition(surface.bottomBar.returnControl.keyboardFace.tint != nil)
        if mode != .letters {
            precondition(surface.bottomBar.fieldControl.isHidden, "A field-specific insert replaced page navigation")
        }
    }
    surface.show(.letters, layout: layout, inputHeight: 269, fieldKeys: .standard)
    precondition(surface.bottomBar.returnControl.keyboardFace.tint == nil, "Normal Return kept a submission tint")
    func rgba(_ color: UIColor, _ traits: UITraitCollection) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b), Double(a)]
    }
    func over(_ foreground: [Double], _ background: [Double]) -> [Double] {
        (0..<3).map { foreground[$0] * foreground[3] + background[$0] * (1 - foreground[3]) } + [1]
    }
    func luminance(_ color: [Double]) -> Double {
        let linear = color.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
    var minimumContrast = Double.infinity
    for native in [false, true] {
    defaults.set(native, forKey: SharedKeys.keyboardIOSStyling)
    for dark in [false, true] {
        for increased in [false, true] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
                                                       UITraitCollection(accessibilityContrast: increased ? .high : .normal)])
            let host = rgba(.secondarySystemBackground, traits)
            let board = over(rgba(KeyboardChromeRole.board.solidFill(increasedContrast: increased), traits), host)
            let input = over(rgba(KeyboardChromeRole.input.solidFill(increasedContrast: increased), traits), board)
            let command = over(rgba(KeyboardChromeRole.control.solidFill(increasedContrast: increased), traits), board)
            if increased {
                precondition(rgba(KeyboardChromeRole.control.solidFill(increasedContrast: true), traits)[3] == 1
                             && rgba(KeyboardChromeRole.board.solidFill(increasedContrast: true), traits)[3] == 1,
                             "Accessibility fallback must use opaque backgrounds")
            }
            for (foreground, background) in [(UIColor.label, input), (.label, command),
                                             (KeyboardChromeRole.secondaryForeground, input),
                                             (KeyboardChromeRole.secondaryForeground, board),
                                             (.saiityOnAction, rgba(.saiityAction, traits))] {
                let front = luminance(over(rgba(foreground, traits), background)), back = luminance(background)
                let contrast = (max(front, back) + 0.05) / (min(front, back) + 0.05)
                precondition(contrast >= 4.5, "Solid keyboard text lost contrast")
                minimumContrast = min(minimumContrast, contrast)
            }
        }
    }
    }
    defaults.set(false, forKey: SharedKeys.keyboardIOSStyling)
    print("PASS: host Return labels and page navigation; Solid contrast, minimum=\\(minimumContrast):1 on fixture backdrop")
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
