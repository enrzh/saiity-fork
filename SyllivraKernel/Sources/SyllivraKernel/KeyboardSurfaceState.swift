import CoreGraphics
import Foundation

/// Emoji-category scrubber values. `KeyboardState` publishes the same numbers
/// so existing Combine subscribers keep working.
public struct KeyboardSurfaceState: Equatable, Sendable {
    public var offset: CGFloat
    public var selectionIndex: Int
    public var expanded: Bool

    public init(offset: CGFloat = 0, selectionIndex: Int = 0, expanded: Bool = false) {
        self.offset = offset
        self.selectionIndex = selectionIndex
        self.expanded = expanded
    }

    public mutating func select(at index: Int) {
        selectionIndex = max(0, index)
    }

    /// Returns false when the published value would not change.
    public mutating func setSelectionIndex(_ index: Int) -> Bool {
        let normalized = max(0, index)
        guard selectionIndex != normalized else { return false }
        selectionIndex = normalized
        return true
    }

    public mutating func setExpanded(_ expanded: Bool) -> Bool {
        guard self.expanded != expanded else { return false }
        self.expanded = expanded
        return true
    }

    public mutating func setOffset(_ offset: CGFloat) -> Bool {
        let normalized = max(0, offset)
        guard abs(self.offset - normalized) > 0.5 else { return false }
        self.offset = normalized
        return true
    }
}
