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

        var built: [[KeyGridKey]] = translate(
            rows,
            // The layout's own command keys are dropped: this page supplies its
            // own shift, delete and bottom bar, and keeping the originals produced
            // two shift keys and two delete keys side by side.
            dropping: suppliedByTheBar,
            glyphSize: 22,
            glyphWeight: .light
        )

        // Shift and delete go on the lowest letter row, pinned to its edges.
        if built.count >= 2 {
            var lowest = built[built.count - 1]
            guard !lowest.isEmpty else {
                return KeyGridPage(
                    id: "letters", rows: built, pinnedLastRow: true,
                    bottomBar: bottomBar()
                )
            }
            lowest.insert(
                KeyGridKey(id: "shift", action: .shift, weight: 1.5,
                           label: "⇧", isCommand: true,
                           glyphSize: 17, glyphWeight: .semibold),
                at: 0
            )
            lowest.append(
                KeyGridKey(id: "delete", action: .deleteRepeating, weight: 1.5,
                           label: "⌫", isCommand: true,
                           glyphSize: 18, glyphWeight: .regular)
            )
            built[built.count - 1] = lowest
        }

        return KeyGridPage(
            id: "letters",
            rows: built,
            pinnedLastRow: true,
            bottomBar: bottomBar()
        )
    }

    /// 123, space, emoji, return — the same four controls every system keyboard
    /// puts there, so the page reads the way a person expects.
    /// The page's rows, translated, with the layout's own command keys removed.
    ///
    /// Spacers are dropped rather than rendered: the layout data pads short rows
    /// with them, and drawing them produced sliver keys at both ends of the home row.
    /// The solver centres short rows on its own, so the padding is not needed.
    private static func translate(
        _ rows: [[KeyDefinition]],
        dropping: Set<String>,
        glyphSize: CGFloat,
        glyphWeight: KeyGlyphWeight
    ) -> [[KeyGridKey]] {
        rows.map { row in
            row.enumerated().compactMap { column, key in
                guard !dropping.contains(key.type.identity) else { return nil }
                return makeKey(
                    key,
                    row: 0,
                    column: column,
                    glyphSize: glyphSize,
                    glyphWeight: glyphWeight
                )
            }
        }
    }

    /// The bottom bar, in the legacy order: 123, emoji, space, period, return.
    ///
    /// Five controls, not four. The period key sits between space and return and
    /// carries a comma hint beneath its dot, which is how the legacy design offered
    /// punctuation without a second key. Its action is the period, matching the
    /// control it replaces.
    private static func bottomBar(
        layerLabel: String = "123",
        pageToggle: KeyGridKey? = nil
    ) -> [KeyGridKey] {
        var keys: [KeyGridKey] = []
        if let pageToggle { keys.append(pageToggle) }
        keys.append(contentsOf: [
            KeyGridKey(
                id: "bar-layer", action: .symbols,
                label: layerLabel, systemImage: nil,
                isCommand: true, isPill: true,
                faceInset: CGSize(width: 8, height: 8),
                glyphSize: 14, glyphWeight: .semibold,
                barWidth: .compact
            ),
            KeyGridKey(
                id: "bar-emoji", action: .emoji,
                label: nil, systemImage: "face.smiling",
                isCommand: true, isPill: true,
                faceInset: CGSize(width: 8, height: 8),
                glyphSize: 16, glyphWeight: .semibold,
                barWidth: .compact
            ),
            KeyGridKey(
                id: "bar-space", action: .space,
                label: spaceLabel,
                isCommand: true, isPill: true,
                faceInset: CGSize(width: 0, height: 4),
                glyphSize: 14, glyphWeight: .semibold,
                barWidth: .flex
            ),
            KeyGridKey(
                id: "bar-period", action: .insert("."),
                label: ".",
                isCommand: false, isPill: false,
                faceInset: CGSize(width: 10, height: 8),
                glyphSize: 19, glyphWeight: .light,
                barWidth: .compact
            ),
            KeyGridKey(
                id: "bar-return", action: .newline,
                label: nil, systemImage: "return",
                isCommand: true, isPill: true,
                faceInset: CGSize(width: 8, height: 8),
                glyphSize: 16, glyphWeight: .semibold,
                barWidth: .wide
            )
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
        // Symbols are drawn smaller and heavier than letters: at 22pt light a "€"
        // or "@" fills its plate and the page stops reading as a keyboard.
        var built = translate(
            rows,
            dropping: suppliedByTheBar,
            glyphSize: 17,
            glyphWeight: .regular
        )
        if var last = built.last, !last.isEmpty {
            last[last.count - 1] = KeyGridKey(
                id: "delete",
                action: .deleteRepeating,
                weight: 1.5,
                label: "⌫",
                isCommand: true,
                glyphSize: 18,
                glyphWeight: .regular
            )
            built[built.count - 1] = last
        }
        // The page toggle lives on the bottom bar rather than stealing a grid row,
        // so the symbol keys keep the same places on both pages. The bar's layer key
        // reads ABC here, which is what distinguishes the two pages at a glance.
        let toggle = KeyGridKey(
            id: "symbolPageToggle",
            action: .page(page == .symbolsNumbers ? "#+=" : "123"),
            weight: 1.2,
            label: page == .symbolsNumbers ? "#+=" : "123",
            isCommand: true,
            isPill: true,
            glyphSize: 15,
            glyphWeight: .medium
        )
        return KeyGridPage(
            id: id,
            rows: built,
            pinnedLastRow: true,
            bottomBar: bottomBar(layerLabel: "ABC", pageToggle: toggle)
        )
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

    /// Key kinds the page supplies itself.
    ///
    /// The shipped layouts already contain a shift, a delete, a layer switch and a
    /// space/return row, and the page supplies its own. Translating both produced two
    /// shift keys, two delete keys and two "123" keys side by side.
    ///
    /// Spacers are deliberately **kept**: they are 0.5-weight keys that indent the
    /// home row, which is why that row is narrower than the row above it. They are
    /// invisible because letter plates have no container, not because they are
    /// absent.
    private static let suppliedByTheBar: Set<String> = [
        "shift", "backspace", "symbols", "shiftSymbols",
        "spacebar", "returnkey"
    ]

    // MARK: - Translation

    /// One legacy key definition into one new key.
    ///
    /// Accent variants are attached here rather than looked up on press, so the
    /// touch handler does no work beyond reading a value it already has.
    private static func makeKey(
        _ key: KeyDefinition,
        row: Int,
        column: Int,
        glyphSize: CGFloat,
        glyphWeight: KeyGlyphWeight
    ) -> KeyGridKey {
        let id = "k-\(row)-\(column)"
        switch key.type {
        case .input(let value, _):
            let variants = AccentedCharacters.accents(for: value) ?? []
            if value.count == 1, !variants.isEmpty {
                return KeyGridKey(
                    id: id,
                    action: .character(base: value, variants: [value] + variants),
                    label: value,
                    glyphSize: glyphSize,
                    glyphWeight: glyphWeight,
                    isInvisiblePlate: true
                )
            }
            return KeyGridKey(id: id, action: .insert(value), label: value,
                              glyphSize: glyphSize, glyphWeight: glyphWeight,
                              isInvisiblePlate: true)
        case .spacer:
            // Carries width so the row indents, and draws nothing.
            return KeyGridKey(id: id, action: .none, weight: 0.5,
                              glyphSize: glyphSize, glyphWeight: glyphWeight)
        default:
            return KeyGridKey(id: id, action: .none, label: nil,
                              glyphSize: glyphSize, glyphWeight: glyphWeight)
        }
    }
}

private extension KeyType {
    /// A stable name for the key's kind, used to filter the layout's own command
    /// keys out of a page that supplies its own.
    var identity: String {
        switch self {
        case .input: return "input"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .spacebar: return "spacebar"
        case .returnkey: return "returnkey"
        case .symbols: return "symbols"
        case .shiftSymbols: return "shiftSymbols"
        case .spacer: return "spacer"
        default: return "other"
        }
    }
}
