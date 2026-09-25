// DictusCore/Sources/DictusCore/NextKeyGridModel.swift
//
// The new keyboard's data layer. A page is a value: a list of rows, each row a
// list of keys. Nothing here knows about UIKit, SwiftUI, or how a touch arrives.
//
// Why a model at all: the previous keyboard had the key layout expressed in one
// place, the drawn plates in a second, and the pressible targets in a third.
// Three descriptions of the same thirty keys, and every bug in the history was
// some disagreement between them. Here there is one list, and everything
// downstream — plates, targets, drawing, hit testing — is derived from it.

import CoreGraphics
import Foundation

/// What a key does when it is pressed.
///
/// Cases carry their own payload so a press never has to look anything up. A
/// closure-based action type was rejected deliberately: a closure per key makes
/// equality meaningless, which makes caching and change detection impossible,
/// and those are what keep a keystroke from rebuilding the grid.
public enum KeyAction: Equatable {
    /// Insert literal text.
    case insert(String)
    /// Insert on press, unless held, in which case offer `variants`.
    case character(base: String, variants: [String])
    case shift
    case delete
    /// Delete, repeating while held.
    case deleteRepeating
    case space
    case newline
    case symbols
    case letters
    case emoji
    /// Switch page, e.g. symbols1 <-> symbols2.
    case page(String)
    case dismiss
    case none
}

/// One key, as data.
public struct KeyGridKey: Equatable {
    public var id: String
    public var action: KeyAction
    /// Relative width. 1 is a standard letter key.
    public var weight: CGFloat
    /// Glyph drawn on the plate. Falls back to a symbol derived from `action`.
    public var label: String?
    /// System image name, for keys drawn as an icon rather than text.
    public var systemImage: String?
    /// Command-sized plates get the wider corner radius and the heavier weight.
    public var isCommand: Bool

    public init(
        id: String,
        action: KeyAction,
        weight: CGFloat = 1,
        label: String? = nil,
        systemImage: String? = nil,
        isCommand: Bool = false
    ) {
        self.id = id
        self.action = action
        self.weight = weight
        self.label = label
        self.systemImage = systemImage
        self.isCommand = isCommand
    }

    /// The glyph to draw, resolved once so the draw path does no work.
    public var resolvedLabel: String {
        if let label { return label }
        switch action {
        case .insert(let text), .character(let text, _): return text
        case .shift: return "⇧"
        case .delete, .deleteRepeating: return "⌫"
        case .space: return "space"
        case .newline: return "return"
        case .symbols, .letters: return "123"
        case .emoji: return "☺"
        case .dismiss: return "⌄"
        case .page(let title): return title
        case .none: return ""
        }
    }

    /// Accent options offered on hold, empty when the key has none.
    public var variants: [String] {
        if case .character(_, let variants) = action { return variants }
        return []
    }
}

/// A whole page of keys.
public struct KeyGridPage: Equatable {
    public var id: String
    public var rows: [[KeyGridKey]]
    /// When true the last row's first and last keys are pinned to the edges.
    ///
    /// Used by the letter rows, where shift and delete must hold the same place
    /// regardless of how many letters sit between them. The bottom bar is *not*
    /// pinned: its space key is wide and sits between 123 and return, so it is
    /// distributed by weight like any other row.
    public var pinnedLastRow: Bool

    public init(id: String, rows: [[KeyGridKey]], pinnedLastRow: Bool = false) {
        self.id = id
        self.rows = rows
        self.pinnedLastRow = pinnedLastRow
    }

    public var isEmpty: Bool { rows.allSatisfy(\.isEmpty) }

    /// A stable identity for the whole page, used to skip redundant work.
    ///
    /// Cheap on purpose: this is compared on every render, and a deep walk of
    /// thirty keys to answer "did anything change" is exactly the kind of cost
    /// that made typing feel heavy.
    public var fingerprint: String {
        var parts: [String] = []
        parts.reserveCapacity(rows.count)
        for row in rows {
            var rowPart = ""
            for key in row {
                rowPart += key.id
                rowPart += ":"
                rowPart += key.resolvedLabel
                rowPart += key.variants.isEmpty ? "|" : "v|"
            }
            parts.append(rowPart)
        }
        return parts.joined(separator: "/")
    }
}

/// A key resolved to a place on screen.
public struct PlacedKey {
    public let key: KeyGridKey
    public let row: Int
    public let column: Int
    /// The rectangle that is drawn.
    public let plate: CGRect
    /// The rectangle that is pressed. Always contains `plate`.
    public let target: CGRect
}

/// Geometry for one page: where every plate is, and what it is.
public struct KeyGridLayout {
    public var placed: [PlacedKey] = []
    /// `placed` grouped by row, for hit testing.
    public var rows: [[PlacedKey]] = []
    /// The union of every target, in the grid's own coordinates.
    public var bounds: CGRect = .zero

    public init() {}

    public func key(at point: CGPoint) -> PlacedKey? {
        for row in rows {
            for item in row where item.target.contains(point) {
                return item
            }
        }
        return nil
    }
}
