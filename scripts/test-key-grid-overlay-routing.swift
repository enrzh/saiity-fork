// Run from the repository root after building DictusApp for a simulator:
// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/test-key-grid-overlay-routing.swift <simulator-udid> <derived-data>
// Compiles the actual production input view, then exercises UIKit hit testing.
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: test-key-grid-overlay-routing.swift <simulator-udid> <derived-data>")
}
let udid = CommandLine.arguments[1]
let products = CommandLine.arguments[2] + "/Build/Products/Debug-iphonesimulator"
let program = """
import UIKit

final class Controls: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

let root = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 402, height: 269), inputViewStyle: .keyboard)
let controls = Controls(frame: root.bounds)
let accessory = UIControl(frame: CGRect(x: 58, y: 0, width: 36, height: 36))
let recovery = UIControl(frame: CGRect(x: 123, y: 100, width: 156, height: 54))
controls.addSubview(accessory)
controls.addSubview(recovery)
let grid = UIView(frame: CGRect(x: 0, y: 40, width: 402, height: 175))
let bar = UIView(frame: CGRect(x: 0, y: 219, width: 402, height: 44))
let pager = UICollectionView(frame: grid.frame, collectionViewLayout: UICollectionViewFlowLayout())
let visual = UIView(frame: root.bounds)
root.addSubview(controls)
root.addSubview(grid)
root.addSubview(bar)
root.addSubview(pager)
root.addSubview(visual)
root.nativeTouchOwners = [grid, bar, controls]

for solid in [false, true] {
    visual.backgroundColor = solid ? .systemFill : .clear
    // Reproduce a visual host becoming interactive and moving above the owners.
    visual.isUserInteractionEnabled = true
    root.bringSubviewToFront(visual)
    grid.layer.zPosition = 500
    precondition(root.hitTest(CGPoint(x: 70, y: 70), with: nil) === grid)
    precondition(root.hitTest(CGPoint(x: 280, y: 240), with: nil) === bar)
    precondition(root.hitTest(CGPoint(x: 76, y: 18), with: nil) === accessory)
    grid.isHidden = true
    precondition(root.hitTest(CGPoint(x: 201, y: 127), with: nil) === recovery)
    recovery.isHidden = true
    root.nativeTouchOwners = [pager, bar, controls]
    for x in stride(from: CGFloat(4), to: 398, by: 13) {
        for y in stride(from: CGFloat(44), to: 211, by: 13) {
            let hit = root.hitTest(CGPoint(x: x, y: y), with: nil)
            precondition(hit === pager || hit?.isDescendant(of: pager) == true,
                         "Blank collection space was stolen by a material host")
        }
    }
    pager.isUserInteractionEnabled = false
    precondition(root.hitTest(CGPoint(x: 70, y: 70), with: nil) === root)
    pager.isUserInteractionEnabled = true
    root.nativeTouchOwners = [grid, bar, controls]
    grid.isHidden = false
    recovery.isHidden = false
}

// A detached owner cannot steal a new controller's touch.
grid.removeFromSuperview()
precondition(root.hitTest(CGPoint(x: 70, y: 70), with: nil) === root)
root.isUserInteractionEnabled = false
precondition(root.hitTest(CGPoint(x: 280, y: 240), with: nil) == nil)
root.isUserInteractionEnabled = true
root.addSubview(grid)
let started = ProcessInfo.processInfo.systemUptime
for _ in 0..<10_000 {
    precondition(root.hitTest(CGPoint(x: 70, y: 70), with: nil) === grid)
}
let microseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000_000 / 10_000
print("MEASURE: simulator root hit test, 10000 samples, \\(microseconds) us/sample")
print("PASS: production routing, both materials, accessory/bar/recovery, empty collection, hidden and detached owners")
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
let sdk = Process()
sdk.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdk.arguments = ["--sdk", "iphonesimulator", "--show-sdk-path"]
let sdkOutput = Pipe()
sdk.standardOutput = sdkOutput
try sdk.run()
sdk.waitUntilExit()
precondition(sdk.terminationStatus == 0)
let sdkPath = String(data: sdkOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    .trimmingCharacters(in: .whitespacesAndNewlines)
try run(["swiftc", "-sdk", sdkPath, "-target", "arm64-apple-ios17.0-simulator",
         "-I", products, "DictusKeyboard/InputView.swift", input.path, "-o", binary.path])
try run(["simctl", "spawn", udid, binary.path])
