// Run with DEVELOPER_DIR set to Xcode and a booted iOS simulator.
// Exercises the production forwarding closure in a real UIKit hierarchy.
import Foundation

let source = try String(contentsOfFile: "DictusKeyboard/KeyboardViewController.swift", encoding: .utf8)
let start = source.range(of: "        controls.forwardHitTest = ")!.upperBound
let end = source.range(of: "\n\n        keyboardModeButton =", range: start..<source.endIndex)!.lowerBound
let closure = String(source[start..<end])
let program = """
import UIKit
final class Overlay: UIView {
    var forwardHitTest: ((CGPoint, UIEvent?) -> UIView?)?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        return forwardHitTest?(point, event)
    }
}
final class Grid: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) && point.y < 120 && point.x > 40
    }
}
final class Controller {
    var hostingController: UIViewController? = UIViewController()
    var keyGridOwner: Grid? = Grid(frame: CGRect(x: 0, y: 0, width: 400, height: 260))
    func run() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 260))
        let host = hostingController!.view!
        host.frame = root.bounds
        let controls = Overlay(frame: root.bounds)
        let owner = keyGridOwner!
        root.addSubview(host)
        root.addSubview(controls)
        root.addSubview(owner)
        owner.layer.zPosition = 200
        root.bringSubviewToFront(controls)
        controls.forwardHitTest = { point, event in host.hitTest(point, with: event) }
        precondition(root.hitTest(CGPoint(x: 80, y: 60), with: nil) === host,
                     "Baseline must reproduce chrome bypassing the grid despite zPosition")
        controls.forwardHitTest = \(closure)
        // Reproduce both layout paths bringing chrome ahead of the grid.
        root.bringSubviewToFront(controls)
        precondition(root.hitTest(CGPoint(x: 80, y: 60), with: nil) === owner,
                     "Chrome swallowed a letter: forwarded into SwiftUI instead of the grid")
        precondition(root.hitTest(CGPoint(x: 20, y: 60), with: nil) === host,
                     "Excluded shift/delete controls must still reach the host")
        precondition(root.hitTest(CGPoint(x: 80, y: 200), with: nil) === host,
                     "Bottom bar must still reach the host")
        owner.isHidden = true
        precondition(root.hitTest(CGPoint(x: 80, y: 60), with: nil) === host)
        print("PASS: letter routing, dedicated controls, bottom bar, inactive grid")
    }
}
Controller().run()
"""
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let input = directory.appendingPathComponent("main.swift")
let binary = directory.appendingPathComponent("routing-check")
try program.write(to: input, atomically: true, encoding: .utf8)
func run(_ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Failed: \(args)")
}
try run(["--sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios17.0-simulator", input.path, "-o", binary.path])
try run(["simctl", "spawn", "booted", binary.path])
