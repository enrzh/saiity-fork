// DictusKeyboard/LetterKeyGridView.swift
import UIKit
import DictusCore

/// The letter keyboard's grid: it draws the keys and it hit-tests them.
///
/// ## Why this exists
///
/// The previous grid split those two jobs. SwiftUI drew thirty key faces while a
/// separate UIKit view above the hosting view resolved touches against a geometry
/// array the SwiftUI side published through a global bus. Two systems described the
/// same keys, and they could disagree: a face could be drawn where no target was,
/// or a target could exist where no face was. Every symptom in the bug history —
/// taps that did nothing, taps that hit a neighbour, a keyboard that went dead
/// after the first letters — is a symptom of that split.
///
/// Here there is one array of plates. Drawing reads it, hit testing reads it, and
/// they cannot drift. There is no SwiftUI in this file, no `UIViewRepresentable`
/// asking SwiftUI to route a touch, and no shared mutable singleton: the controller
/// owns one instance and hands it a delegate.
///
/// ## Why insert happens on touch-down
///
/// A character that appears when the finger lifts is indistinguishable from a key
/// that ignored you. Input keys therefore commit in `touchesBegan`, which is also
/// what giellakbd-ios — this project's own Apache-2.0 ancestor — does via
/// `KeyType.triggersOnTouchDown` in its `handleTouches`.
///
/// Accent keys are the deliberate exception. Holding one has to be able to commit
/// the option the user picked from the popup rather than the base letter, so those
/// keys wait for touch-up. That is the same rule the system keyboard uses.
protocol LetterKeyGridViewDelegate: AnyObject {
    func letterGrid(_ view: LetterKeyGridView, didInsert text: String)
    func letterGridDidTapDelete(_ view: LetterKeyGridView)
    func letterGridDidTapSymbols(_ view: LetterKeyGridView)
}

final class LetterKeyGridView: UIView {
    weak var delegate: LetterKeyGridViewDelegate?

    // MARK: - Page

    enum Page: Equatable {
        case normal
        case shifted
        case capslock
    }

    private(set) var page: Page = .normal

    // MARK: - Geometry
    //
    // `plates` is the single source of truth: the rectangles that are drawn and
    // the rectangles that are hit. `tiles` is the same row set widened to cover the
    // whole grid so no point inside it is unowned — see
    // `KeyboardKeyHitGeometry.contiguousTiles`.

    private var plates: [[CGRect]] = []
    private(set) var tiles: [[CGRect]] = []
    private var definitions: [[KeyDefinition]] = []
    private var contentSignature: String = ""

    /// The pressed key per finger, keyed by touch identity.
    ///
    /// Keyed by touch rather than by key so two fingers on two keys cannot
    /// overwrite each other, which is how one of the two characters used to vanish.
    private struct ActiveTouch {
        let row: Int
        let column: Int
        let isAccentKey: Bool
        let variantOptions: [String]
        var popupShown: Bool
        var selectedOption: Int
        /// Cancellable, unlike a bare `asyncAfter`: a hold that lifts before the
        /// threshold must not fire a popup for a touch that no longer exists.
        var popupWork: DispatchWorkItem?
    }

    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]
    /// The one popup that may be on screen. A second finger on another accent key
    /// must still type, so it types its base letter and shows no popup.
    private var popupOwner: ObjectIdentifier?

    private var lastShiftTap: TimeInterval = 0

    /// Width of the command plates (shift, delete). Supplied by the surface because
    /// it comes from the shared page layout, and shift and delete must keep exactly
    /// the frames every other surface gives them.
    private var commandKeyWidth: CGFloat = 44

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
        // Never exclusive: one finger per key is the point.
        isExclusiveTouch = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        rebuildGeometry()
    }

    /// Recomputes plates and tiles from the current page and bounds.
    ///
    /// Kept as cheap arithmetic on already-parsed layout data: it runs on a bounds
    /// change, never per keystroke. The old implementation rebuilt all of this on
    /// every SwiftUI render, which is the work that made fast typing lag.
    private func rebuildGeometry() {
        let layout = definitions
        guard !layout.isEmpty else {
            plates = []
            tiles = []
            return
        }
        let metrics = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(bounds.width))
        let edgeInset = metrics.keyGridInset
        let keySpacing = metrics.keySpacing
        let rowSpacing = metrics.keyRowSpacing
        let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
            in: bounds.height,
            rowSpacing: rowSpacing
        )
        let weights = layout.map { row in
            row.map { CGFloat($0.size.width) }
        }
        var solved = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
            for: weights,
            in: bounds.size,
            spacing: keySpacing,
            inset: edgeInset,
            rowSpacing: rowSpacing,
            lastRowHeight: lastRowHeight,
            maxRowHeight: metrics.letterKeyHeight
        )

        // The bottom row is pinned edge to edge so shift and delete keep the same
        // frames as every other surface, instead of floating inside the row.
        if let row = solved.last, let first = row.first, !row.isEmpty {
            solved[solved.count - 1] = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                itemCount: row.count,
                rowFrame: CGRect(x: edgeInset, y: first.minY,
                                 width: max(0, bounds.width - edgeInset * 2),
                                 height: lastRowHeight),
                spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing),
                commandWidth: commandKeyWidth
            )
        }

        // Only as many rows as we actually have keys: the solver can return fewer
        // when the available height is degenerate, and reading past the end used to
        // trap outright and kill the extension on launch.
        let rowCount = min(layout.count, solved.count)
        guard rowCount > 0 else {
            plates = []
            tiles = []
            return
        }
        var newPlates: [[CGRect]] = []
        for rowIndex in 0..<rowCount {
            let row = layout[rowIndex]
            // Zip rather than index: a short solved row must not shift every
            // following key by one column.
            newPlates.append(Array(zip(row, solved[rowIndex]).map { $1 }))
        }
        plates = newPlates
        tiles = KeyboardKeyHitGeometry.contiguousTiles(
            for: plates,
            in: bounds,
            labels: labelRows,
            probabilities: prediction
        )
    }

    /// Single-character labels per row, in the same order as `plates`. Only real
    /// letters take part in hit prediction.
    private var labelRows: [[String?]] {
        definitions.prefix(plates.count).map { row in
            row.map { key in
                guard case .input(let value, _) = key.type, value.count == 1 else { return nil }
                return value
            }
        }
    }

    private var prediction: NextCharacterProbabilities? {
        KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
            ? SuggestionState.shared.adaptiveTouchPrediction
            : nil
    }

    private var commandKeyWidthFromLayout: CGFloat { commandKeyWidth }

    // MARK: - Content

    /// Installs the letter rows and redraws.
    ///
    /// The rows are the unshifted set: this view applies the shift page itself when
    /// it draws, because it owns the glyphs. A second copy of the page kept by the
    /// caller would be a second source of truth that can disagree with the screen.
    ///
    /// `KeyDefinition` is not `Equatable`, so the change check uses a cheap content
    /// signature. Rebuilding geometry is arithmetic on already-parsed layout data,
    /// but doing it on every render is the work that used to make typing lag.
    func setDefinitions(_ definitions: [[KeyDefinition]], commandWidth: CGFloat) {
        let signature = Self.signature(definitions)
        let changed = self.contentSignature != signature || self.commandKeyWidth != commandWidth
        self.definitions = definitions
        self.contentSignature = signature
        self.commandKeyWidth = commandWidth
        if changed {
            rebuildGeometry()
        }
        setNeedsDisplay()
    }

    /// Advances the shift page, returning the new one.
    ///
    /// A single shift applies to exactly one character and then falls back, which is
    /// what every other keyboard does and what stops a forgotten shift turning a
    /// whole word uppercase.
    private func advanceShift() {
        page = page == .normal ? .shifted : .normal
        setNeedsDisplay()
    }

    private static func signature(_ definitions: [[KeyDefinition]]) -> String {
        definitions.map { row in
            row.map { key in
                if case .input(let value, _) = key.type { return value }
                return "."
            }.joined(separator: ",")
        }.joined(separator: "/")
    }

    /// Drops any in-flight gesture and returns to the unshifted page.
    func reset() {
        cancelAllTouches()
        page = .normal
        setNeedsDisplay()
    }

    private func cancelAllTouches() {
        for active in activeTouches.values {
            active.popupWork?.cancel()
        }
        activeTouches.removeAll()
        popupOwner = nil
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let pressed = pressedPositions()
        for (rowIndex, row) in plates.enumerated() {
            for (column, plate) in row.enumerated() {
                guard rowIndex < definitions.count, column < definitions[rowIndex].count else { continue }
                let key = definitions[rowIndex][column]
                let isPressed = pressed.contains(Position(row: rowIndex, column: column))
                drawKey(key, plate: plate, isPressed: isPressed, context: context)
            }
        }
        drawPopupIfNeeded()
    }

    private struct Position: Hashable {
        let row: Int
        let column: Int
    }

    private func pressedPositions() -> Set<Position> {
        Set(activeTouches.values.map { Position(row: $0.row, column: $0.column) })
    }

    private func drawKey(
        _ key: KeyDefinition,
        plate: CGRect,
        isPressed: Bool,
        context: CGContext
    ) {
        let radius: CGFloat
        switch key.type {
        case .shift, .backspace, .symbols, .returnkey, .spacebar:
            radius = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius
        default:
            radius = VoiceOnlyKeyboardPolicy.keyCornerRadius
        }
        let path = UIBezierPath(roundedRect: plate, cornerRadius: radius)
        context.saveGState()
        // The plate is a visual. Whether it is Liquid Glass or a solid fill is the
        // design's business and never affects input, so it is resolved here from the
        // same preference the SwiftUI chrome uses.
        context.setFillColor(plateColor(isPressed: isPressed).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()

        drawGlyph(for: key, in: plate, isPressed: isPressed)
    }

    private func plateColor(isPressed: Bool) -> UIColor {
        if isPressed { return UIColor.label.withAlphaComponent(0.14) }
        if KeyboardInteractionPreferences.liquidGlassEnabled {
            return UIColor.secondarySystemFill.withAlphaComponent(0.55)
        }
        return UIColor.tertiarySystemFill
    }

    private func drawGlyph(for key: KeyDefinition, in plate: CGRect, isPressed: Bool) {
        let text: String
        let size: CGFloat
        let weight: UIFont.Weight
        switch key.type {
        case .input(let value, _):
            text = displayed(value)
            size = 22
            weight = .light
        case .shift:
            text = page == .capslock ? "⇪" : (page == .shifted ? "⇧" : "⇧")
            size = 17
            weight = .semibold
        case .backspace:
            text = "⌫"
            size = 19
            weight = .regular
        case .symbols, .shiftSymbols:
            text = "123"
            size = 15
            weight = .medium
        case .returnkey:
            text = "return"
            size = 15
            weight = .regular
        case .spacebar:
            text = "space"
            size = 15
            weight = .regular
        default:
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.label.withAlphaComponent(isPressed ? 0.6 : 1),
            .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let measured = string.size()
        let origin = CGPoint(
            x: plate.midX - measured.width / 2,
            y: plate.midY - measured.height / 2
        )
        string.draw(at: origin)
    }

    private func displayed(_ value: String) -> String {
        switch page {
        case .normal: return value
        case .shifted, .capslock: return value.uppercased()
        }
    }

    private func drawPopupIfNeeded() {
        guard let owner = popupOwner,
              let active = activeTouches[owner],
              active.popupShown,
              active.variantOptions.count > 1,
              active.row < plates.count,
              active.column < plates[active.row].count else { return }
        let plate = plates[active.row][active.column]
        let options = active.variantOptions
        let width = CGFloat(options.count) * 44
        let frame = CGRect(
            x: min(max(0, plate.midX - width / 2), max(0, bounds.width - width)),
            y: max(0, plate.minY - 58),
            width: width,
            height: 54
        )
        let path = UIBezierPath(roundedRect: frame, cornerRadius: 12)
        UIColor.secondarySystemBackground.setFill()
        path.fill()
        UIColor.separator.setStroke()
        path.lineWidth = 1
        path.stroke()

        for (index, option) in options.enumerated() {
            let cell = CGRect(
                x: frame.minX + CGFloat(index) * 44,
                y: frame.minY,
                width: 44,
                height: frame.height
            )
            if index == active.selectedOption {
                UIColor.label.withAlphaComponent(0.12).setFill()
                UIBezierPath(roundedRect: cell.insetBy(dx: 2, dy: 2), cornerRadius: 9).fill()
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            NSAttributedString(
                string: option,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraph
                ]
            ).draw(at: CGPoint(x: cell.midX - 11, y: cell.midY - 13))
        }
    }

    // MARK: - Hit testing

    private func keyIndex(at point: CGPoint) -> (row: Int, column: Int)? {
        KeyboardKeyHitResolver.keyIndex(at: point, rows: tiles)
    }

    private func isDedicatedControl(_ key: KeyDefinition) -> Bool {
        switch key.type {
        case .shift, .backspace, .spacebar:
            return true
        default:
            return false
        }
    }

    private func variants(for key: KeyDefinition) -> [String] {
        guard case .input(let value, _) = key.type,
              value.count == 1,
              let accents = AccentedCharacters.accents(for: value),
              !accents.isEmpty else { return [] }
        let cased = (page == .shifted || page == .capslock)
            ? accents.map { $0.uppercased() }
            : accents
        return [value] + cased
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let index = keyIndex(at: point) else { continue }
            guard index.row < definitions.count, index.column < definitions[index.row].count else { continue }
            let key = definitions[index.row][index.column]

            switch key.type {
            case .shift:
                HapticFeedback.playInputClick()
                advanceShift()
            case .backspace:
                HapticFeedback.playInputClick()
                delegate?.letterGridDidTapDelete(self)
            case .symbols, .shiftSymbols:
                HapticFeedback.playInputClick()
                delegate?.letterGridDidTapSymbols(self)
            case .spacer:
                continue
            case .input(let value, _):
                guard !isDedicatedControl(key) else { continue }
                let identity = ObjectIdentifier(touch)
                let options = variants(for: key)
                HapticFeedback.playInputClick()
                if options.count > 1 {
                    // A held accent key must not stop a second finger typing, so only
                    // one popup is ever shown and the other touch types its base.
                    let ownsPopup = popupOwner == nil
                    if ownsPopup { popupOwner = identity }
                    var active = ActiveTouch(
                        row: index.row, column: index.column,
                        isAccentKey: true, variantOptions: options,
                        popupShown: false, selectedOption: 0
                    )
                    if ownsPopup {
                        let work = DispatchWorkItem { [weak self] in
                            self?.showPopup(for: identity)
                        }
                        active.popupWork = work
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + KeyboardDeletion.holdRecognitionDuration,
                            execute: work
                        )
                    }
                    activeTouches[identity] = active
                } else {
                    activeTouches[identity] = ActiveTouch(
                        row: index.row, column: index.column,
                        isAccentKey: false, variantOptions: [],
                        popupShown: false, selectedOption: 0
                    )
                    delegate?.letterGrid(self, didInsert: displayed(value))
                }
                setNeedsDisplay()
            default:
                continue
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let identity = ObjectIdentifier(touch)
            guard var active = activeTouches[identity],
                  popupOwner == identity,
                  active.popupShown,
                  active.row < plates.count,
                  active.column < plates[active.row].count else { continue }
            let frame = CGRect(
                x: 0, y: 0,
                width: CGFloat(active.variantOptions.count) * 44,
                height: 54
            )
            let plate = plates[active.row][active.column]
            let popupOrigin = CGPoint(
                x: min(max(0, plate.midX - frame.width / 2), max(0, bounds.width - frame.width)),
                y: max(0, plate.minY - 58)
            )
            let index = KeyVariantPopup.selectedIndex(
                at: touch.location(in: self),
                popupFrame: frame.offsetBy(dx: popupOrigin.x, dy: popupOrigin.y),
                optionCount: active.variantOptions.count
            )
            guard index != active.selectedOption else { continue }
            active.selectedOption = index
            activeTouches[identity] = active
            HapticFeedback.variantHighlightChanged()
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A cancelled touch is terminal, and for a key grid it means the finger left
        // without committing. Anything else leaves the character unaccounted for.
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            let identity = ObjectIdentifier(touch)
            guard let active = activeTouches.removeValue(forKey: identity) else { continue }
            active.popupWork?.cancel()
            if popupOwner == identity { popupOwner = nil }
            guard active.isAccentKey,
                  active.row < definitions.count,
                  active.column < definitions[active.row].count else {
                setNeedsDisplay()
                continue
            }
            let key = definitions[active.row][active.column]
            if active.popupShown,
               active.variantOptions.indices.contains(active.selectedOption) {
                delegate?.letterGrid(self, didInsert: active.variantOptions[active.selectedOption])
            } else {
                // Released before the popup appeared: the base letter, as tapped.
                if case .input(let value, _) = key.type {
                    delegate?.letterGrid(self, didInsert: displayed(value))
                }
            }
        }
        setNeedsDisplay()
    }

    private func showPopup(for identity: ObjectIdentifier) {
        guard popupOwner == identity, var active = activeTouches[identity] else { return }
        active.popupShown = true
        active.popupWork = nil
        activeTouches[identity] = active
        HapticFeedback.variantPopupPresented()
        setNeedsDisplay()
    }
}
