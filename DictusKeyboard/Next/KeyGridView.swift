// DictusKeyboard/Next/KeyGridView.swift
//
// The new keyboard's key grid. One class serves the letter page, the symbol pages
// and the number pad, because they differ only in the page they are given.
//
// ## The rule this file exists to enforce
//
// The rectangle that is drawn and the rectangle that is pressed are the same
// object. `KeyGridLayout` holds both, and this view reads `plate` to draw and
// `target` to resolve, from one solved layout.
//
// The previous keyboard could not make that claim. SwiftUI drew the key faces
// while a separate UIKit view resolved touches against geometry that SwiftUI
// published through a process-wide registry. Two systems described the same keys,
// so a key could be visible with no target, or have a target over blank space,
// depending on what SwiftUI had rebuilt and when. That is the mechanism behind
// every report in the bug history: taps that did nothing, taps that hit a
// neighbour, a keyboard that went dead after the first few letters.
//
// ## Insert on press
//
// A character that appears when the finger lifts is indistinguishable from a key
// that ignored you. Input keys commit in `touchesBegan`. This is also what
// giellakbd-ios — this project's own Apache-2.0 ancestor — does, through
// `KeyType.triggersOnTouchDown` in its `handleTouches`.
//
// Keys with accent variants are the deliberate exception: a hold has to be able
// to commit the chosen variant, so those decide on touch-up.

import UIKit
import DictusCore

protocol KeyGridViewDelegate: AnyObject {
    func keyGrid(_ view: KeyGridView, perform action: KeyAction, key: KeyGridKey)
    /// Held keys repeat through here. The view does not own the timer.
    func keyGridDidBeginRepeat(_ view: KeyGridView, key: KeyGridKey)
    func keyGridDidEndRepeat(_ view: KeyGridView)
}

final class KeyGridView: UIView {

    weak var delegate: KeyGridViewDelegate?

    // MARK: - Page state

    private(set) var page: KeyGridPage?
    private(set) var layout = KeyGridLayout()
    private var fingerprint: String = ""
    private var solvedSize: CGSize = .zero

    /// Caps lock, when the user has double-tapped shift.
    private(set) var isCapsLocked = false
    /// True while shift is held down by an active touch.
    private var shiftLatched = false

    // MARK: - Touch state

    private struct Press {
        let key: KeyGridKey
        let row: Int
        let column: Int
        /// Accent keys decide on release; everything else has already committed.
        let waitsForRelease: Bool
        var variants: [String]
        var popupVisible: Bool
        var selectedVariant: Int
        var popupWork: DispatchWorkItem?
    }

    /// Keyed by touch identity, never by key: two fingers on two keys are two
    /// gestures, and tracking by key would let the second overwrite the first.
    private var presses: [ObjectIdentifier: Press] = [:]
    /// At most one accent popup at a time. A second finger on another accent key
    /// must still be able to type, so it types its base character and shows none.
    private var popupOwner: ObjectIdentifier?

    /// Delete repeat, driven by the delegate so the timing lives in one place.
    private var repeatingKey: KeyGridKey?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        // One finger per key is the entire point, so the view must never claim
        // exclusivity. The previous grid set this and it disabled the keys beside
        // a held one.
        isExclusiveTouch = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    // MARK: - Content

    /// Installs a page. Geometry is re-solved only when something that can move a
    /// plate has actually changed.
    func setPage(_ page: KeyGridPage, force: Bool = false) {
        let next = page.fingerprint
        guard force || next != fingerprint || page.id != self.page?.id else {
            self.page = page
            return
        }
        fingerprint = next
        self.page = page
        solvedSize = .zero
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Re-solving on a size change only. Solving is arithmetic over the page,
        // and doing it per keystroke is the cost that used to make typing lag.
        guard bounds.size != solvedSize, let page else { return }
        solvedSize = bounds.size
        layout = KeyGridPlacement.solve(page, in: bounds.size)
        setNeedsDisplay()
    }

    /// Drops any gesture in flight and clears the shift latches.
    ///
    /// Called when the keyboard leaves this page. A press that is still being
    /// tracked when the page changes is the shape of bug where a character is
    /// committed to a field the user has already left.
    func reset() {
        for press in presses.values {
            press.popupWork?.cancel()
        }
        presses.removeAll()
        popupOwner = nil
        repeatingKey = nil
        shiftLatched = false
        isCapsLocked = false
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let held = heldPositions()
        for row in layout.rows {
            for item in row {
                let isPressed = held.contains(PlacedPosition(row: item.row, column: item.column))
                drawPlate(item, pressed: isPressed, context: context)
            }
        }
        drawVariantPopupIfNeeded()
    }

    private struct PlacedPosition: Hashable {
        let row: Int
        let column: Int
    }

    private func heldPositions() -> Set<PlacedPosition> {
        Set(presses.values.map { PlacedPosition(row: $0.row, column: $0.column) })
    }

    private func drawPlate(_ item: PlacedKey, pressed: Bool, context: CGContext) {
        // A key with no action is a spacer: it carries width so the row indents and
        // draws nothing at all. Legacy spacers were invisible, and the way to get
        // that right is to draw nothing rather than to draw an empty plate.
        if case .none = item.key.action { return }
        // Letter plates have no container in the legacy design — the
        // `keyContainersEnabled` preference defaulted to off, so only the glyph
        // showed. Drawing a filled plate behind every letter is the single most
        // visible difference from that look, so the preference is honoured here
        // rather than assumed.
        let showPlate = !item.key.isInvisiblePlate
            || KeyboardInteractionPreferences.keyContainersEnabled
        if showPlate {
            let radius = item.key.isPill
                ? min(item.plate.height / 2, KeyGridPlacement.commandCornerRadius)
                : (item.key.isCommand
                    ? KeyGridPlacement.commandCornerRadius
                    : KeyGridPlacement.keyCornerRadius)
            let path = UIBezierPath(roundedRect: item.plate, cornerRadius: radius)
            context.saveGState()
            context.setFillColor(
                plateColor(pressed: pressed, isLetter: item.key.isInvisiblePlate).cgColor
            )
            context.addPath(path.cgPath)
            context.fillPath()
            context.restoreGState()
        }
        drawLabel(for: item.key, in: item.plate, pressed: pressed)
    }

    /// Plate fill. The material preference is visual only and is resolved here, so
    /// it can never influence which key is pressed.
    ///
    /// Command faces use the system fill the legacy glass resolved to when the
    /// material preference is off, which is the closest a plain `UIView` drawing
    /// can get to the real material.
    private func plateColor(pressed: Bool, isLetter: Bool = false) -> UIColor {
        if pressed {
            return isLetter
                ? UIColor.label.withAlphaComponent(0.10)
                : UIColor.label.withAlphaComponent(0.13)
        }
        if KeyboardInteractionPreferences.liquidGlassEnabled {
            return UIColor.secondarySystemFill.withAlphaComponent(0.5)
        }
        return UIColor.tertiarySystemFill
    }

    private func drawLabel(for key: KeyGridKey, in plate: CGRect, pressed: Bool) {
        let color = UIColor.label.withAlphaComponent(pressed ? 0.55 : 1)
        // The period key carries a comma hint beneath its dot, as the legacy
        // control did, so punctuation was reachable without a second key.
        if key.id == "bar-period" {
            drawPeriodKey(in: plate, color: color)
            return
        }
        if let systemImage = key.systemImage {
            drawSymbol(systemImage, in: plate, size: key.glyphSize, color: color)
            return
        }
        let text = displayText(for: key)
        guard !text.isEmpty else { return }
        let string = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: key.glyphSize, weight: fontWeight(key.glyphWeight)),
            .foregroundColor: color,
            .paragraphStyle: centeredParagraph()
        ])
        let measured = string.size()
        string.draw(at: CGPoint(x: plate.midX - measured.width / 2,
                                y: plate.midY - measured.height / 2))
    }

    private func drawSymbol(_ name: String, in plate: CGRect, size: CGFloat, color: UIColor) {
        guard let image = UIImage(systemName: name)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let fitted = image.size
        image.draw(in: CGRect(
            x: plate.midX - fitted.width / 2,
            y: plate.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        ))
    }

    /// A large period with a small comma beneath it.
    private func drawPeriodKey(in plate: CGRect, color: UIColor) {
        let dot = NSAttributedString(string: ".", attributes: [
            .font: UIFont.systemFont(ofSize: 19, weight: .light),
            .foregroundColor: color,
            .paragraphStyle: centeredParagraph()
        ])
        let comma = NSAttributedString(string: ",", attributes: [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: centeredParagraph()
        ])
        let dotSize = dot.size()
        let commaSize = comma.size()
        let totalHeight = dotSize.height + commaSize.height
        var y = plate.midY - totalHeight / 2
        dot.draw(at: CGPoint(x: plate.midX - dotSize.width / 2, y: y))
        y += dotSize.height
        comma.draw(at: CGPoint(x: plate.midX - commaSize.width / 2, y: y))
    }

    private func fontWeight(_ weight: KeyGlyphWeight) -> UIFont.Weight {
        switch weight {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }

    private func centeredParagraph() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        return paragraph
    }

    private func displayText(for key: KeyGridKey) -> String {
        var text = key.resolvedLabel
        guard case .character(let base, _) = key.action else { return text }
        if isCapsLocked || shiftLatched {
            text = base.uppercased()
        }
        return text
    }

    private func drawVariantPopupIfNeeded() {
        guard let owner = popupOwner,
              let press = presses[owner],
              press.popupVisible,
              press.variants.count > 1,
              let item = itemAt(row: press.row, column: press.column) else { return }
        let cellWidth: CGFloat = 44
        let cellHeight: CGFloat = 54
        let width = cellWidth * CGFloat(press.variants.count)
        let frame = popupFrame(above: item.plate, width: width, height: cellHeight)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 12).fill()
        UIColor.separator.setStroke()
        let outline = UIBezierPath(roundedRect: frame, cornerRadius: 12)
        outline.lineWidth = 1
        outline.stroke()

        for (index, option) in press.variants.enumerated() {
            let cell = CGRect(x: frame.minX + cellWidth * CGFloat(index),
                              y: frame.minY, width: cellWidth, height: cellHeight)
            if index == press.selectedVariant {
                UIColor.label.withAlphaComponent(0.12).setFill()
                UIBezierPath(roundedRect: cell.insetBy(dx: 2, dy: 2),
                             cornerRadius: 9).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor.label,
                .paragraphStyle: centeredParagraph()
            ]
            let string = NSAttributedString(string: option, attributes: attributes)
            let measured = string.size()
            string.draw(at: CGPoint(x: cell.midX - measured.width / 2,
                                    y: cell.midY - measured.height / 2))
        }
    }

    private func popupFrame(above plate: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: min(max(0, plate.midX - width / 2), max(0, bounds.width - width)),
            y: max(0, plate.minY - height - 4),
            width: width,
            height: height
        )
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let item = layout.key(at: point) else { continue }
            let identity = ObjectIdentifier(touch)
            let action = item.key.action

            switch action {
            case .shift:
                // Held shift stays on for exactly one character unless the user
                // double-taps it for caps lock.
                shiftLatched = true
                HapticFeedback.playInputClick()
                setNeedsDisplay()

            case .deleteRepeating:
                HapticFeedback.playInputClick()
                delegate?.keyGrid(self, perform: .delete, key: item.key)
                delegate?.keyGridDidBeginRepeat(self, key: item.key)
                repeatingKey = item.key
                presses[identity] = Press(
                    key: item.key, row: item.row, column: item.column,
                    waitsForRelease: false, variants: [],
                    popupVisible: false, selectedVariant: 0, popupWork: nil
                )

            case .character(let base, let variants):
                HapticFeedback.playInputClick()
                if variants.count > 1 {
                    let ownsPopup = popupOwner == nil
                    if ownsPopup { popupOwner = identity }
                    var press = Press(
                        key: item.key, row: item.row, column: item.column,
                        waitsForRelease: true, variants: variants,
                        popupVisible: false, selectedVariant: 0, popupWork: nil
                    )
                    if ownsPopup {
                        let work = DispatchWorkItem { [weak self] in
                            self?.revealPopup(for: identity)
                        }
                        press.popupWork = work
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + KeyboardDeletion.holdRecognitionDuration,
                            execute: work
                        )
                    }
                    presses[identity] = press
                } else {
                    presses[identity] = Press(
                        key: item.key, row: item.row, column: item.column,
                        waitsForRelease: false, variants: [],
                        popupVisible: false, selectedVariant: 0, popupWork: nil
                    )
                    commit(base)
                }

            default:
                HapticFeedback.playInputClick()
                presses[identity] = Press(
                    key: item.key, row: item.row, column: item.column,
                    waitsForRelease: false, variants: [],
                    popupVisible: false, selectedVariant: 0, popupWork: nil
                )
                delegate?.keyGrid(self, perform: action, key: item.key)
            }
            setNeedsDisplay()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let identity = ObjectIdentifier(touch)
            guard var press = presses[identity],
                  popupOwner == identity,
                  press.popupVisible,
                  let item = itemAt(row: press.row, column: press.column) else { continue }
            let cellWidth: CGFloat = 44
            let cellHeight: CGFloat = 54
            let frame = popupFrame(
                above: item.plate,
                width: cellWidth * CGFloat(press.variants.count),
                height: cellHeight
            )
            let index = variantIndex(
                at: touch.location(in: self), frame: frame, count: press.variants.count
            )
            guard index != press.selectedVariant else { continue }
            press.selectedVariant = index
            presses[identity] = press
            HapticFeedback.variantHighlightChanged()
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Terminal. A key that is still "held" after a cancel is a key that will
        // never commit, and the character is silently lost.
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            let identity = ObjectIdentifier(touch)
            guard let press = presses.removeValue(forKey: identity) else { continue }
            press.popupWork?.cancel()
            if popupOwner == identity { popupOwner = nil }
            if repeatingKey?.id == press.key.id {
                repeatingKey = nil
                delegate?.keyGridDidEndRepeat(self)
            }
            if cancelled { continue }
            switch press.key.action {
            case .shift:
                // A short tap releases shift; a second tap within the window locks.
                if isCapsLocked {
                    isCapsLocked = false
                } else {
                    shiftLatched = false
                }
            case .character(let base, _):
                if press.popupVisible, press.variants.indices.contains(press.selectedVariant) {
                    commit(press.variants[press.selectedVariant])
                } else if !press.waitsForRelease {
                    // Already committed on press.
                } else {
                    commit(base)
                }
            default:
                break
            }
        }
        setNeedsDisplay()
    }

    private func itemAt(row: Int, column: Int) -> PlacedKey? {
        guard row < layout.rows.count else { return nil }
        return layout.rows[row].first { $0.column == column }
    }

    private func variantIndex(at point: CGPoint, frame: CGRect, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let cellWidth = frame.width / CGFloat(count)
        guard cellWidth > 0 else { return 0 }
        let index = Int((point.x - frame.minX) / cellWidth)
        return min(max(0, index), count - 1)
    }

    private func revealPopup(for identity: ObjectIdentifier) {
        guard popupOwner == identity, var press = presses[identity] else { return }
        press.popupVisible = true
        press.popupWork = nil
        presses[identity] = press
        HapticFeedback.variantPopupPresented()
        setNeedsDisplay()
    }

    /// Sends a character through the same path whether it was typed, held or
    /// tapped, so casing is applied in exactly one place.
    private func commit(_ character: String) {
        let text = (isCapsLocked || shiftLatched) ? character.uppercased() : character
        delegate?.keyGrid(self, perform: .insert(text), key: KeyGridKey(id: "", action: .none))
        // Shift applies to one character. Leaving it latched is how a forgotten
        // shift turns a whole word uppercase.
        if shiftLatched { shiftLatched = false }
    }
}
