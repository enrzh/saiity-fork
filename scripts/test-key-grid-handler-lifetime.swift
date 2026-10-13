// Run from the repository root: swift scripts/test-key-grid-handler-lifetime.swift
// Executes the production registration code with a UIKit-free owner double.
import Foundation

let source = try String(contentsOfFile: "DictusKeyboard/KeyGridTouchOwner.swift", encoding: .utf8)
let start = source.range(of: "final class KeyGridHandlers {")!.lowerBound
let end = source.range(of: "/// Geometry for one key grid:", range: start..<source.endIndex)!.lowerBound
let support = """
import Foundation
import CoreGraphics
struct KeyGridPress {
    let keyID: String
    let id = UUID().uuidString
}
final class KeyGridTouchOwner {
    enum Gesture { case press, move, release }
    var onGesture: ((Gesture, KeyGridPress, CGPoint, Bool) -> Void)?
    var activeHandlers: KeyGridHandlers?
    var excludedRects: [CGRect] = []
    var claimsRect: CGRect?
    var rows: [[CGRect]] = []
    func setGeometry(rows: [[CGRect]], keyIDs: [[String]]) { self.rows = rows }
}
struct KeyGridGeometry {
    var rows: [[CGRect]] = [[CGRect(x: 8, y: 40, width: 40, height: 40)]]
    var keyIDs: [[String]] = [["key-0"]]
    var excludedRects: [CGRect] = []
    var gridRect = CGRect(x: 8, y: 40, width: 40, height: 40)
}
enum ProbeEvent {
    case diagnosticProbe(component: String, instanceID: String, action: String, details: String)
}
enum PersistentLog {
    static var orphaned = 0
    static func log(_ event: ProbeEvent) { orphaned += 1 }
}
"""
let checks = """
var calls: [String] = []
weak var registered: KeyGridHandlers?
let owner = KeyGridTouchOwner()
KeyGridTouchBus.attach(owner) // Controller loads before the surface appears.
func renderSurface() {
    let temporary = KeyGridHandlers()
    registered = temporary
    temporary.onPress = { _, _ in calls.append("press") }
    temporary.onMove = { _, _ in calls.append("move") }
    temporary.onRelease = { _, _ in calls.append("release") }
    KeyGridTouchBus.activate(geometry: KeyGridGeometry(), handlers: temporary)
}
renderSurface() // SwiftUI's temporary body/closures may now be discarded.
precondition(registered != nil, "Active key handlers were deallocated: ABC resolves taps with no listener")
let press = KeyGridPress(keyID: "key-0")
owner.onGesture?(.press, press, .zero, false)
owner.onGesture?(.move, press, .zero, false)
owner.onGesture?(.release, press, .zero, false)
precondition(calls == ["press", "move", "release"], "A complete touch must reach the active surface")
precondition(PersistentLog.orphaned == 0)

weak var replacement: KeyGridHandlers?
func replaceSurface() {
    let next = KeyGridHandlers()
    replacement = next
    next.onRelease = { _, _ in calls.append("replacement") }
    KeyGridTouchBus.activate(geometry: KeyGridGeometry(), handlers: next)
}
replaceSurface()
precondition(registered == nil, "Replacing a surface must release its old handlers")
owner.onGesture?(.release, press, .zero, false)
precondition(calls.last == "replacement", "Dispatch must use the current registration")
KeyGridTouchBus.deactivate()
precondition(replacement == nil, "Deactivation must release the retained registration")
precondition(owner.claimsRect == nil && owner.rows.isEmpty)
print("Key-grid handler lifecycle passed: late activation, retention, dispatch, replacement, teardown")
"""
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "-"]
let input = Pipe()
process.standardInput = input
try process.run()
input.fileHandleForWriting.write(Data((support + "\n" + source[start..<end] + "\n" + checks).utf8))
try input.fileHandleForWriting.close()
process.waitUntilExit()
exit(process.terminationStatus)
