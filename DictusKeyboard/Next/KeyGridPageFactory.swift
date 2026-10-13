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
import SyllivraKernel

enum KeyGridPageFactory {

    /// The page shown for a keyboard area.
    enum Page {
        case letters
        case symbolsNumbers
        case symbolsPunctuation
    }

    // MARK: - Letters

    /// Distance from the top of the grid area to the top of the first key row.
    ///
    /// Measured, not chosen: on the system keyboard the panel's top edge is at 547pt
    /// and the first letter row's top at 598pt, and the grid area starts below the
    /// accessory lane — so 19pt into the area.
    ///
    /// This is the number that keeps the keys off the bottom of the bar on a screen
    /// taller than the one it was measured on. The block hangs from here rather than
    /// resting on the bottom of whatever height it is handed, so a taller surface
    /// grows the gap above the lane instead of pushing the letters down.
    static let letterGridTopInset: CGFloat = 19

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
        var rows = KeyboardVariantLayout.rows(for: .active)
        if KeyboardLayouts.drawsDigitRow { rows.insert(Array("1234567890").map(String.init), at: 0) }
        var built = rows.enumerated().map { row, values in
            values.enumerated().map { column, value in
                let variants = KeyboardVariantPreferences.options(for: value, kind: .letter)
                return KeyGridKey(id: "letter-\(row)-\(column)",
                    action: variants.count > 1 ? .character(base: value, variants: variants) : .insert(value),
                    label: value, glyphSize: 22, glyphWeight: .regular, isInvisiblePlate: true)
            }
        }

        // Shift and delete go on the lowest letter row, pinned to its edges.
        if built.count >= 2 {
            var lowest = built[built.count - 1]
            guard !lowest.isEmpty else {
                return KeyGridPage(id: "letters", rows: built, pinnedLastRow: true)
            }
            lowest.insert(
                KeyGridKey(id: "shift", action: .shift, weight: 1.5,
                           label: "⇧", systemImage: "shift.fill",
                           isCommand: true,
                           glyphSize: CommandKeyStyle.glyphSize,
                           glyphWeight: CommandKeyStyle.glyphWeight),
                at: 0
            )
            lowest.append(
                KeyGridKey(id: "delete", action: .deleteRepeating, weight: 1.5,
                           label: "⌫", systemImage: CommandKeyStyle.deleteSymbolName, isCommand: true,
                           glyphSize: CommandKeyStyle.glyphSize,
                           glyphWeight: CommandKeyStyle.glyphWeight)
            )
            built[built.count - 1] = lowest
        }

        return KeyGridPage(id: "letters", rows: built, pinnedLastRow: true,
                          topInset: KeyGridPageFactory.letterGridTopInset)
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
        glyphWeight: KeyGlyphWeight,
        symbolVariants: Bool = false
    ) -> [[KeyGridKey]] {
        // Spacers go as well as the keys in `dropping`.
        //
        // The layout data pads the home row with two half-width spacers, which was
        // the right idea under a solver that shared width out by key count and the
        // wrong one here: they turned nine letters into an eleven-key row, and
        // eleven keys is what the standard letter width was then derived from. Nine
        // keys at the standard width, centred, is exactly what the platform draws —
        // measured at x=26.5..375 with 33.5pt keys against x=7..395 above it.
        let skip = dropping.union(["spacer"])
        return rows.map { row in
            row.enumerated().compactMap { column, key in
                guard !skip.contains(key.type.identity) else { return nil }
                return makeKey(
                    key,
                    row: 0,
                    column: column,
                    glyphSize: glyphSize,
                    glyphWeight: glyphWeight,
                    symbolVariants: symbolVariants
                )
            }
        }
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
        // Nothing is dropped here. `KeyboardSymbolsLayout` is three rows of real
        // content — the last one is the page toggle, the punctuation keys and
        // delete — and the shared `AuxiliaryBottomBar` now owns the rail that used
        // to live in a fourth row.
        //
        // This used to remove the last row unconditionally, on the assumption that
        // every symbols page ended in a space/return rail. That is true of
        // `KeyboardLayout.numbersRows` and false of the layout actually in use, so
        // it was deleting a row of punctuation and leaving the page two rows deep
        // with the remaining rows stretched to fill.

        let id = page == .symbolsNumbers ? "symbols1" : "symbols2"
        // Symbols are drawn smaller and heavier than letters: at 22pt light a "€"
        // or "@" fills its plate and the page stops reading as a keyboard.
        var built = translate(
            rows,
            dropping: suppliedByTheBar,
            glyphSize: 17,
            glyphWeight: .regular,
            symbolVariants: true
        )
        if var last = built.last, !last.isEmpty {
            // Appended, not substituted. `translate` *removes* the layout's own
            // page toggle and delete, so this row is already short by two keys and
            // has to gain them back. Overwriting the last cell instead destroyed
            // the apostrophe, which is how the row came out one key short of the
            // system's seven.
            last.append(
                KeyGridKey(
                    id: "delete",
                    action: .deleteRepeating,
                    weight: 2.25,
                    label: "⌫",
                    systemImage: CommandKeyStyle.deleteSymbolName,
                    isCommand: true,
                    glyphSize: CommandKeyStyle.glyphSize,
                    glyphWeight: CommandKeyStyle.glyphWeight
                )
            )
            built[built.count - 1] = last
        }
        // The page toggle leads the last row rather than stealing a slot from the
        // symbol keys. `AuxiliaryBottomBar` is shared with the letter and emoji
        // pages and cannot draw a "#+=" label, so the toggle stays here — which is
        // also where `SymbolKeyboardSurface` keeps its own equivalent.
        if var last = built.last, !last.isEmpty {
            last.insert(
                KeyGridKey(
                    id: "symbolPageToggle",
                    action: .page(page == .symbolsNumbers ? "#+=" : "123"),
                    weight: 1.4,
                    label: page == .symbolsNumbers ? "#+=" : "123",
                    isCommand: true,
                    glyphSize: CommandKeyStyle.textSize,
                    glyphWeight: CommandKeyStyle.glyphWeight
                ),
                at: 0
            )
            built[built.count - 1] = last
        }
        return KeyGridPage(id: id, rows: built, pinnedLastRow: true,
                        topInset: KeyGridPageFactory.letterGridTopInset)
    }

    // MARK: - Number pad

    /// The 3×4 pad shown for numeric host fields.
    ///
    /// Digits are inserted on press, and holding one opens the letter keyboard —
    /// the behaviour the system keyboard offers, so a numeric field does not trap
    /// the user.
    static func numberPad(style: HostFieldPolicy.NumberPadStyle) -> KeyGridPage {
        let digits: [[(String, CGFloat, Bool)]] = [
            [("1", 1, false), ("2", 1, false), ("3", 1, false)],
            [("4", 1, false), ("5", 1, false), ("6", 1, false)],
            [("7", 1, false), ("8", 1, false), ("9", 1, false)]
        ]
        var rows = digits.enumerated().map { rowIndex, row in
            row.enumerated().map { column, entry in
                digitKey(label: entry.0, row: rowIndex, column: column, style: style)
            }
        }
        let leading = style == .digits
            ? KeyGridKey(id: "pad-letters", action: .letters, label: "ABC", isCommand: true)
            : digitKey(label: style == .phone ? "*" : (Locale.current.decimalSeparator ?? "."), row: 3, column: 0)
        rows.append([
            leading,
            digitKey(label: "0", row: 3, column: 1, style: style),
            KeyGridKey(id: "pad-delete", action: .deleteRepeating, systemImage: CommandKeyStyle.deleteSymbolName, isCommand: true,
                       glyphSize: CommandKeyStyle.glyphSize,
                       glyphWeight: CommandKeyStyle.glyphWeight)
        ])
        // Taller keys than the letter grid, because the pad has four rows and spends
        // none of its height on a bottom bar. Measured: 48pt against the letters' 43.
        return KeyGridPage(id: "numberPad", rows: rows, rowHeight: 48, rowSpacing: 6,
                        topInset: KeyGridPageFactory.letterGridTopInset)
    }

    private static func digitKey(label: String, row: Int, column: Int,
                                 style: HostFieldPolicy.NumberPadStyle = .digits) -> KeyGridKey {
        let variants = style == .phone ? KeyboardVariantPreferences.options(for: label, kind: .phone)
            : KeyboardVariantPreferences.options(for: label, kind: .symbol)
        return KeyGridKey(
            id: "pad-\(row)-\(column)",
            action: variants.count > 1
                ? .character(base: label, variants: variants)
                : .insert(label),
            label: label,
            glyphSize: 22,
            glyphWeight: .regular
        )
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
        glyphWeight: KeyGlyphWeight,
        symbolVariants: Bool
    ) -> KeyGridKey {
        let id = "k-\(row)-\(column)"
        switch key.type {
        case .input(let value, _):
            let variants = symbolVariants
                ? KeyboardVariantPreferences.options(for: value, kind: .symbol)
                : KeyboardVariantPreferences.options(for: value, kind: .letter)
            if value.count == 1, variants.count > 1 {
                return KeyGridKey(
                    id: id,
                    action: .character(base: value, variants: variants),
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
        case .fullStop:
            // The period key gets comma and other punctuation variants on hold.
            let variants = KeyboardVariantPreferences.options(for: ".", kind: .symbol)
            return KeyGridKey(
                id: id,
                action: .character(base: ".", variants: variants),
                label: ".",
                glyphSize: glyphSize,
                glyphWeight: glyphWeight,
                isInvisiblePlate: true
            )
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
