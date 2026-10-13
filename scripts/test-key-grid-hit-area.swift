// Run from the repo root with DEVELOPER_DIR set to Xcode and a booted simulator.
import Foundation

let source = try String(contentsOfFile: "DictusKeyboard/KeyGridTouchOwner.swift", encoding: .utf8)
let start = source.range(of: "final class KeyGridTouchOwner: UIView {")!.lowerBound
let end = source.range(of: "/// The callbacks a key surface supplies", range: start..<source.endIndex)!.lowerBound
let production = String(source[start..<end])
let pressStart = source.range(of: "struct KeyGridPress {")!.lowerBound
let pressEnd = source.range(of: "\n}", range: pressStart..<source.endIndex)!.upperBound

// The real geometry, not a hand-written stand-in: the point of this probe is that
// the published tiles and the owner's hit testing agree.
let geometrySource = try String(
    contentsOfFile: "SyllivraKernel/Sources/SyllivraKernel/AdaptiveTouchRouting.swift",
    encoding: .utf8)
let geometryStart = geometrySource.range(of: "public struct NextCharacterProbabilities")!.lowerBound
let geometry = String(geometrySource[geometryStart...])
    .replacingOccurrences(of: "public ", with: "")

let program = """
import UIKit
\(source[pressStart..<pressEnd])
\(geometry)
enum ProbeEvent { case diagnosticProbe(component: String, instanceID: String, action: String, details: String) }
enum PersistentLog { static func log(_ event: ProbeEvent) {} }
enum KeyGridTouchBus { static func reportOrphanedGesture() {} }
protocol KeyGridTouchOwnerDelegate: AnyObject {}
final class KeyGridHandlers {
    var onMove: ((KeyGridPress, CGPoint) -> Void)?
    var onRelease: ((KeyGridPress, Bool) -> Void)?
}
extension KeyGridTouchOwner { enum Gesture { case press, move, release } }
\(production)
let grid = KeyGridTouchOwner(frame: CGRect(x: 0, y: 0, width: 180, height: 130))
grid.setGeometry(rows: [[CGRect(x: 30, y: 20, width: 40, height: 45),
                         CGRect(x: 70, y: 20, width: 40, height: 45),
                         CGRect(x: 110, y: 20, width: 40, height: 45)]],
                 keyIDs: [["left", "middle", "delete"]])
grid.claimsRect = CGRect(x: 15, y: 10, width: 150, height: 80)
grid.excludedRects = [CGRect(x: 110, y: 20, width: 40, height: 45)]
func hit(_ x: CGFloat, _ y: CGFloat) -> Bool {
    grid.point(inside: CGPoint(x: x, y: y), with: nil)
}
precondition(hit(25, 40), "Near left edge must resolve to the letter")
precondition(hit(30, 40) && hit(70, 40), "Letter plates must remain reachable")
precondition(!hit(10, 40) && !hit(20, 10), "Do not claim outside grid or rows")
precondition(!hit(110, 40) && !hit(151, 40), "Do not take delete or its edge")
precondition(!hit(50, 70), "Do not swallow an unresolved vertical gap")
final class Finger: UITouch {
    /// The point this touch reports. Settable so a probe can aim somewhere
    /// specific; the original two-finger checks below rely on the default.
    var point = CGPoint(x: 40, y: 40)
    override func location(in view: UIView?) -> CGPoint { point }
}
let first = Finger()
let second = Finger()
let handlers = KeyGridHandlers()
var began: [String] = []
var ended: [String] = []
var replacedCallbackRan = false
handlers.onRelease = { press, cancelled in
    precondition(!cancelled)
    ended.append(press.id)
}
grid.activeHandlers = handlers
grid.onGesture = { _, press, _, _ in began.append(press.id) }
grid.touchesBegan([first], with: nil)
grid.touchesBegan([second], with: nil)
precondition(began.count == 2 && Set(began).count == 2,
             "Two fingers on the same key must have distinct interaction IDs")
handlers.onRelease = { _, _ in replacedCallbackRan = true }
grid.touchesEnded([second], with: nil)
precondition(grid.hasActiveTouches, "Lifting the second finger must retain the first")
grid.touchesEnded([first], with: nil)
precondition(ended == began.reversed() && !replacedCallbackRan,
             "Each release must reach its original callback exactly once")
grid.touchesEnded([first, second], with: nil)
precondition(ended.count == 2 && !grid.hasActiveTouches)

// Contiguous tiles: the shape a real keyboard uses. The cell is the target and
// the plate is decoration inset inside it, so every point across the grid belongs
// to exactly one key — including the margins beside the first and last key.
let plates = [[CGRect(x: 34, y: 24, width: 36, height: 40),
               CGRect(x: 76, y: 24, width: 36, height: 40)]]
let gridBounds = CGRect(x: 18, y: 12, width: 144, height: 76)
let tiles = KeyboardKeyHitGeometry.contiguousTiles(for: plates, in: gridBounds)
precondition(tiles[0].count == 2)
precondition(tiles[0][0].minX == gridBounds.minX, "the left margin must belong to the first key")
precondition(tiles[0][1].maxX == gridBounds.maxX, "the right margin must belong to the last key")
precondition(tiles[0][0].maxX == tiles[0][1].minX, "tiles must share an edge, not a gap")

let forgiving = KeyGridTouchOwner(frame: gridBounds)
forgiving.setGeometry(rows: tiles, keyIDs: [["left", "right"]])
forgiving.claimsRect = gridBounds
forgiving.activeHandlers = KeyGridHandlers()
var resolvedKeys: [String] = []
forgiving.onGesture = { _, press, _, _ in resolvedKeys.append(press.keyID) }

func forgivingKeyID(_ x: CGFloat, _ y: CGFloat) -> String? {
    resolvedKeys.removeAll()
    let touch = Finger()
    touch.point = CGPoint(x: x, y: y)
    forgiving.touchesBegan([touch], with: nil)
    defer { forgiving.touchesEnded([touch], with: nil) }
    return resolvedKeys.first
}

// Every sampled point in the grid must press exactly one key.
for step in 0..<24 {
    for rowStep in 0..<12 {
        let x = gridBounds.minX + gridBounds.width * CGFloat(step) / 24
        let y = gridBounds.minY + gridBounds.height * CGFloat(rowStep) / 12
        let keyID = forgivingKeyID(x, y)
        precondition(keyID != nil, "a point inside the claimed grid must never be dead")
        precondition(keyID == "left" || keyID == "right", "a resolved key must be a real key")
    }
}
// The margins beside the outer keys are live, and each plate still gets itself.
precondition(forgivingKeyID(20, 40) == "left", "the left margin must press the first key")
precondition(forgivingKeyID(160, 40) == "right", "the right margin must press the last key")
precondition(forgivingKeyID(50, 40) == "left", "the left plate must press the left key")
precondition(forgivingKeyID(95, 40) == "right", "the right plate must press the right key")
precondition(forgivingKeyID(19, 13) == "left", "the grid corner must belong to a key")

print("PASS: letter edge, dedicated control, and unowned areas")
print("PASS: overlapping same-key fingers, callback refresh, independent release, no duplicate commits")
print("PASS: contiguous tiles leave no dead point, and the outer margins are live")
"""
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let input = directory.appendingPathComponent("main.swift")
let binary = directory.appendingPathComponent("key-grid-hit-check")
try program.write(to: input, atomically: true, encoding: .utf8)
func run(_ args: [String]) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    task.arguments = args
    try task.run()
    task.waitUntilExit()
    precondition(task.terminationStatus == 0, "Failed: \(args)")
}
try run(["--sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios17.0-simulator", input.path, "-o", binary.path])
try run(["simctl", "spawn", "booted", binary.path])
