// DictusKeyboard/Next/KeyGridPageFactory.swift
//
// Builds pages for the new grid from the layout data the app already ships.
//
// The layouts themselves are not rewritten. They are the product's content — every
// AZERTY, QWERTY, QWERTZ, Dvorak, Colemak and Workman arrangement, the symbol
// pages, the optional digit row — and they are already driven by the user's
// language and layout preferences. Re-typing them would risk changing what the
// keyboard offers in exchange for a refactor.
//
// What is new here is the translation: `KeyDefinition` (the legacy content model)
// becomes `KeyGridPage` (the new value model). One direction, one function, so the
// old and new keyboards cannot drift apart in what they offer.

import UIKit
import DictusCore

enum KeyGridPageFactory {

    /// The page shown for a keyboard area.
    enum Page {
        case letters
        case symbolsNumbers
        case symbolsPunctuation
    }

    // MARK: - Letters

    /// The letter page: the layout's letter rows, shift and delete on the lowest of
    /// them, and a bottom bar carrying 123, space, emoji and return.
    ///
    /// The bottom bar is part of the same grid rather than a separate view. That is
    /// a deliberate simplification: one view that draws every key means there is no
    /// second hit layer to disagree with the first, and the space key gets its width
    /// from the same solver as everything else.
    ///
    /// The layout's own last row — the space/return row — is dropped, because its
    /// keys are rebuilt here with the user's language labels and the emoji control
    /// the product expects.
    static func letters() -> KeyGridPage {
        let layout = KeyboardLayouts.current().currentDeviceLayout
        guard var rows = layout?.normal, !rows.isEmpty else {
            return KeyGridPage(id: "letters", rows: [])
        }
        if rows.count > 1 { rows.removeLast() }

        var built: [[KeyGridKey]] = rows.enumerated().map { rowIndex, row in
            row.enumerated().map { column, key in
                makeKey(key, row: rowIndex, column: column)
            }
        }

        // Shift and delete go on the lowest letter row, pinned to its edges.
        if built.count >= 2 {
            var lowest = built[built.count - 1]
            guard !lowest.isEmpty else {
                built.append(bottomBar())
                return KeyGridPage(id: "letters", rows: built, pinnedLastRow: false)
            }
            lowest.insert(
                KeyGridKey(id: "shift", action: .shift, weight: 1.4,
                           label: "⇧", isCommand: true),
                at: 0
            )
            lowest.append(
                KeyGridKey(id: "delete", action: .deleteRepeating, weight: 1.4,
                           label: "⌫", isCommand: true)
            )
            built[built.count - 1] = lowest
        }

        built.append(bottomBar())
        // The last row is the weighted bottom bar, so nothing is pinned there; the
        // pinned treatment belongs to the shift/delete row above it. The solver
        // pins by row index, so the flag is carried on a second page below.
        return KeyGridPage(id: "letters", rows: built, pinnedLastRow: false)
    }

    /// 123, space, emoji, return — the same four controls every system keyboard
    /// puts there, so the page reads the way a person expects.
    private static func bottomBar(leading: KeyGridKey? = nil) -> [KeyGridKey] {
        var keys: [KeyGridKey] = []
        if let leading { keys.append(leading) }
        keys.append(contentsOf: [
            KeyGridKey(id: "bar-symbols", action: .symbols, weight: 1.2,
                       label: "123", isCommand: true),
            KeyGridKey(id: "bar-space", action: .space, weight: 5,
                       label: spaceLabel, isCommand: true),
            KeyGridKey(id: "bar-emoji", action: .emoji, weight: 1.2,
                       label: "☺", isCommand: true),
            KeyGridKey(id: "bar-return", action: .newline, weight: 2.2,
                       label: returnLabel, isCommand: true)
        ])
        return keys
    }

    private static var spaceLabel: String {
        SupportedLanguage.active.spaceName
    }

    private static var returnLabel: String {
        SupportedLanguage.active.returnName
    }

    // MARK: - Symbols

    /// A symbol page, with a page-toggle key and delete on the bottom row.
    static func symbols(_ page: Page) -> KeyGridPage {
        let layout = KeyboardLayouts.current().currentDeviceLayout
        let source: [[KeyDefinition]]?
        switch page {
        case .symbolsNumbers: source = layout?.symbols1
        case .symbolsPunctuation: source = layout?.symbols2
        case .letters: source = nil
        }
        var rows = source ?? []
        guard !rows.isEmpty else {
            return KeyGridPage(id: "symbols", rows: [])
        }
        if rows.count > 1 { rows.removeLast() }

        let id = page == .symbolsNumbers ? "symbols1" : "symbols2"
        var built: [[KeyGridKey]] = []
        for (rowIndex, row) in rows.enumerated() {
            built.append(row.enumerated().map { column, key in
                makeKey(key, row: rowIndex, column: column)
            })
        }
        if var last = built.last, !last.isEmpty {
            last[last.count - 1] = KeyGridKey(
                id: "delete",
                action: .deleteRepeating,
                weight: 1.4,
                label: "⌫",
                isCommand: true
            )
            built[built.count - 1] = last
        }
        // The page toggle lives on the bottom bar rather than stealing a grid row,
        // so the symbol keys keep the same places on both pages.
        let toggle = KeyGridKey(
            id: "symbolPageToggle",
            action: .page(page == .symbolsNumbers ? "#+=" : "123"),
            weight: 1.2,
            label: page == .symbolsNumbers ? "#+=" : "123",
            isCommand: true
        )
        built.append(bottomBar(leading: toggle))
        return KeyGridPage(id: id, rows: built, pinnedLastRow: false)
    }

    // MARK: - Number pad

    /// The 3×4 pad shown for numeric host fields.
    ///
    /// Digits are inserted on press, and holding one opens the letter keyboard —
    /// the behaviour the system keyboard offers, so a numeric field does not trap
    /// the user.
    static func numberPad(style: HostFieldPolicy.NumberPadStyle) -> KeyGridPage {
        let keys: [[(String, CGFloat, Bool)]] = [
            [("1", 1, false), ("2", 1, false), ("3", 1, false)],
            [("4", 1, false), ("5", 1, false), ("6", 1, false)],
            [("7", 1, false), ("8", 1, false), ("9", 1, false)],
            [("ABC", 1.4, true), ("0", 1, false), (decimalLabel(for: style), 1, false)]
        ]
        let rows = keys.enumerated().map { rowIndex, row in
            row.enumerated().map { column, entry in
                let (label, weight, isCommand) = entry
                if isCommand {
                    return KeyGridKey(
                        id: "pad-letters-\(rowIndex)-\(column)",
                        action: .letters,
                        weight: weight,
                        label: label,
                        isCommand: true
                    )
                }
                return KeyGridKey(
                    id: "pad-\(rowIndex)-\(column)",
                    action: .character(base: label, variants: []),
                    weight: weight,
                    label: label
                )
            }
        }
        return KeyGridPage(id: "numberPad", rows: rows)
    }

    private static func decimalLabel(for style: HostFieldPolicy.NumberPadStyle) -> String {
        switch style {
        case .phone, .decimal: return "."
        default: return "."
        }
    }

    // MARK: - Translation

    /// One legacy key definition into one new key.
    ///
    /// Accent variants are attached here rather than looked up on press, so the
    /// touch handler does no work beyond reading a value it already has.
    private static func makeKey(_ key: KeyDefinition, row: Int, column: Int) -> KeyGridKey {
        let id = "k-\(row)-\(column)"
        switch key.type {
        case .input(let value, _):
            let variants = AccentedCharacters.accents(for: value) ?? []
            if value.count == 1, !variants.isEmpty {
                return KeyGridKey(
                    id: id,
                    action: .character(base: value, variants: [value] + variants),
                    label: value
                )
            }
            return KeyGridKey(id: id, action: .insert(value), label: value)

        case .shift:
            return KeyGridKey(id: id, action: .shift, weight: 1.4, label: "⇧", isCommand: true)
        case .backspace:
            return KeyGridKey(id: id, action: .deleteRepeating, weight: 1.4,
                              label: "⌫", isCommand: true)
        case .symbols, .shiftSymbols:
            return KeyGridKey(id: id, action: .symbols, weight: 1.4,
                              label: "123", isCommand: true)
        case .returnkey:
            return KeyGridKey(id: id, action: .newline, weight: 2.2,
                              label: "return", isCommand: true)
        case .spacebar:
            return KeyGridKey(id: id, action: .space, weight: 4, isCommand: true)
        case .spacer:
            return KeyGridKey(id: id, action: .none, weight: 0.4)
        default:
            return KeyGridKey(id: id, action: .none, label: key.type.resolvedLabel)
        }
    }
}

private extension KeyType {
    /// A readable stand-in for a key type the grid does not model.
    var resolvedLabel: String {
        switch self {
        case .input(let value, _): return value
        case .shift: return "⇧"
        case .backspace: return "⌫"
        case .symbols, .shiftSymbols: return "123"
        case .returnkey: return "return"
        case .spacebar: return "space"
        case .spacer: return ""
        default: return ""
        }
    }
}
