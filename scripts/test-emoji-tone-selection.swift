// Run from the repository root: swift scripts/test-emoji-tone-selection.swift
// Executes the production geometry without UIKit or the unrelated package targets.
import Foundation

let source = try String(contentsOfFile: "DictusKeyboard/Views/EmojiPickerView.swift", encoding: .utf8)
let categoryBar = try String(contentsOfFile: "DictusKeyboard/Views/EmojiCategoryBar.swift", encoding: .utf8)
let root = try String(contentsOfFile: "DictusKeyboard/KeyboardRootView.swift", encoding: .utf8)
assert(source.contains("filler.isUserInteractionEnabled = false"), "empty recents fillers must not steal the pager pan")
assert(source.contains("panHost.isUserInteractionEnabled = false"), "blank Recents space stays with the collection view pan")
assert(root.contains("EmojiCategoryBar("), "category bookmarks float over the emoji grid")
assert(root.contains("boardDeleteFrame"), "emoji delete uses the shared command frame")
assert(source.contains("EmojiNavigation.landingCategoryID"), "empty recents uses the shared landing policy")
assert(source.contains("topEdgeEffect.isHidden = true"), "iOS 26 top edge effect is disabled")
assert(!source.contains(".offset(y: -3)"), "emoji grid is not negatively offset into the top edge")
assert(source.contains("return max(0, usable / rows)"), "four rows fit without a minimum-height overflow")
assert(source.contains("availableItemCount: itemCount"), "scroll requests check collection data")
assert(source.contains("boundsWidth: Double(collectionView.bounds.width)"), "scroll requests check collection layout")
assert(source.contains("func retryPendingScroll(in collectionView"), "pending scrolls retry from layout")
assert(categoryBar.contains("interactionBounds.contains(point)"), "category hit testing stays in the control frame")
assert(categoryBar.contains("!isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01"), "category hit testing fails closed")
assert(categoryBar.contains("accessibilityAddTraits(.isButton)"), "category icons expose VoiceOver button semantics")
assert(!categoryBar.contains("override func touchesBegan"), "category tracking has one touch lifecycle")
assert(!categoryBar.contains("override func touchesMoved"), "category tracking has one touch lifecycle")
assert(!categoryBar.contains("override func touchesEnded"), "category tracking has one touch lifecycle")
let start = source.range(of: "private enum EmojiToneHitTesting {")!.lowerBound
let end = source.range(of: "// End emoji tone hit testing.")!.lowerBound
let checks = """
let key = CGRect(x: 100, y: 100, width: 44, height: 44)
let bubble = CGRect(x: 6, y: 40, width: 276, height: 56)
for offset in [CGFloat(0), 390, 3900] {
    let source = key.offsetBy(dx: offset, dy: 0)
    let popup = bubble.offsetBy(dx: offset, dy: 0)
    func hit(_ x: CGFloat, _ y: CGFloat) -> Int {
        EmojiToneHitTesting.selectedIndex(at: CGPoint(x: x + offset, y: y),
            source: source, popup: popup, optionCount: 6, initialIndex: 3)
    }
    for index in 0..<6 {
        assert(hit(34 + CGFloat(index) * 44, 68) == index, "Every tone follows the finger")
    }
    assert(hit(122, 122) == 2, "Selection follows the horizontal finger position")
    assert(hit(122, 98) == 2, "Vertical movement does not cancel selection")
    assert(hit(122, 300) == 2, "Dragging outside the popup keeps selection active")
    assert(hit(122, 122) == 2, "Returning after vertical movement keeps selection active")
    assert(hit(0, 68) == 0 && hit(290, 68) == 5, "Horizontal edge slop clamps")
}
assert(EmojiToneHitTesting.selectedIndex(at: CGPoint(x: 220, y: 22),
    source: CGRect(x: 200, y: 0, width: 44, height: 44),
    popup: CGRect(x: 6, y: 4, width: 276, height: 56),
    optionCount: 6, initialIndex: 0) == 4, "Overlapping popup wins over source")
assert(EmojiToneHitTesting.selectedIndex(at: .zero, source: .zero, popup: .zero,
    optionCount: 0, initialIndex: 0) == -1)
print("Emoji tone geometry checks passed (all tones, scroll offsets, Recents, cancellation, overlap).")
"""
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "-"]
let input = Pipe()
process.standardInput = input
try process.run()
input.fileHandleForWriting.write(Data(("import Foundation\nimport CoreGraphics\n" + source[start..<end] + "\n" + checks).utf8))
try input.fileHandleForWriting.close()
process.waitUntilExit()
exit(process.terminationStatus)
