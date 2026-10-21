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
import SwiftUI
import SyllivraKernel

protocol KeyGridViewDelegate: AnyObject {
    func keyGrid(_ view: KeyGridView, perform action: KeyAction, key: KeyGridKey)
    /// Held keys repeat through here. The view does not own the timer.
    func keyGridDidBeginRepeat(_ view: KeyGridView, key: KeyGridKey)
    func keyGridDidEndRepeat(_ view: KeyGridView)
    func keyGridDidRequestDictation(_ view: KeyGridView)
}

final class KeyGridView: UIView {

    weak var delegate: KeyGridViewDelegate?
    private let keypadVoice = KeyboardKeyTouchControl()
    private let keypadLetters = KeyboardKeyTouchControl()

    // MARK: - Page state

    private(set) var page: KeyGridPage?
    private(set) var layout = KeyGridLayout()
    private var neutralLayout = KeyGridLayout()
    private var hitPrediction: NextCharacterProbabilities?
    private var fingerprint: String = ""
    private var solvedSize: CGSize = .zero

    /// Caps lock, when the user has double-tapped shift.
    private(set) var isCapsLocked = false
    /// True while shift is armed for exactly the next character.
    private var shiftLatched = false

    /// The shift touch currently down, if any.
    ///
    /// The shift key has to be tracked like every other key. Without an entry here
    /// `touchesEnded` bails on its first `guard` and the release logic below is
    /// never reached — which is why a second tap could never engage caps lock.
    private var shiftTouch: ObjectIdentifier?
    /// When shift was last released, for the double-tap window.
    private var lastShiftRelease: TimeInterval = 0

    /// Two taps closer together than this mean caps lock, as on the system keyboard.
    private static let capsLockWindow: TimeInterval = 0.35

    /// Whether the next character should be uppercased.
    private var shiftActive: Bool { isCapsLocked || shiftLatched }

    /// A one-shot shift is spent by the first character; caps lock is not.
    private func consumeOneShotShift() {
        if shiftLatched && !isCapsLocked { shiftLatched = false }
    }

    /// Decide what a shift tap meant, once it is released.
    ///
    /// One tap arms the next character. A second tap inside the window locks caps.
    /// A tap while locked switches straight back off.
    ///
    /// That last case is the one that was wrong. The cycle used to run
    /// off → one-shot → locked → off through `isCapsLocked.toggle()` on every tap
    /// inside the window, so leaving caps lock took *three* rapid taps: one to be
    /// counted as the second tap of a pair, one to toggle off, and the state only
    /// settled if a third landed inside 350ms. The platform leaves caps lock in one
    /// tap from the locked state, and so does this.
    private func resolveShiftTap() {
        let now = ProcessInfo.processInfo.systemUptime
        if isCapsLocked {
            // Out of caps lock. The next character is lower case, which is what the
            // platform does: the tap that cancels caps does not also arm a shift.
            isCapsLocked = false
            shiftLatched = false
        } else if now - lastShiftRelease < Self.capsLockWindow {
            // Two taps inside the window lock caps. Checked before the toggle, or a
            // double tap reads as toggle-on then toggle-off and caps is unreachable.
            isCapsLocked = true
            shiftLatched = false
        } else {
            // A tap outside the window toggles the one-shot shift: off if it was on.
            // Re-arming an already-armed shift is what made a second tap look inert.
            shiftLatched.toggle()
            isCapsLocked = false
        }
        lastShiftRelease = now
    }

    // MARK: - Touch state

    private struct Press {
        let key: KeyGridKey
        let row: Int
        let column: Int
        let previewText: String?
        /// Accent keys decide on release; everything else has already committed.
        var waitsForRelease: Bool
        var variants: [String]
        var popupVisible: Bool
        var selectedVariant: Int
        var popupWork: KeyboardHoldSession?
    }

    /// Keyed by touch identity, never by key: two fingers on two keys are two
    /// gestures, and tracking by key would let the second overwrite the first.
    private var presses: [ObjectIdentifier: Press] = [:]
    /// At most one accent popup at a time. A second finger on another accent key
    /// must still be able to type, so it types its base character and shows none.
    private var popupOwner: ObjectIdentifier?
    private var previewOwner: ObjectIdentifier?
    private var variantPopupHost: UIHostingController<KeyVariantPopup>?
    private var previewPopupHost: UIHostingController<KeyPressPreviewHost>?
    private var previewPopupIdentity: ObjectIdentifier?
    private var publishedCommandSpecs: [CommandSpec] = []

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
        keypadVoice.isHidden = true
        keypadVoice.isAccessibilityElement = true
        keypadVoice.accessibilityTraits = .button
        keypadVoice.accessibilityLabel = "Open dictation board"
        keypadVoice.accessibilityIdentifier = "pad-dictation-board"
        keypadVoice.onBegan = { [weak self] _ in
            guard let self, !self.keypadVoice.isHidden, self.page?.id == "numberPad" else { return }
            HapticFeedback.playInputClick()
            self.delegate?.keyGridDidRequestDictation(self)
        }
        addSubview(keypadVoice)
        keypadLetters.isHidden = true
        keypadLetters.isAccessibilityElement = true
        keypadLetters.accessibilityTraits = .button
        keypadLetters.accessibilityLabel = "Open letter keyboard"
        keypadLetters.accessibilityIdentifier = "pad-letter-switch"
        keypadLetters.configurePageSwitch(tap: { [weak self] in
            guard let self, let key = self.layout.placed.first(where: { $0.key.id == "pad-letters" })?.key else { return }
            self.delegate?.keyGrid(self, perform: .letters, key: key)
        }, hold: { [weak self] in
            guard let self else { return }
            self.delegate?.keyGridDidRequestDictation(self)
        }, holdLabel: "Open dictation board")
        addSubview(keypadLetters)
    }

    // MARK: - Content

    /// Installs a page. Geometry is re-solved only when something that can move a
    /// plate has actually changed.
    func setPage(_ page: KeyGridPage, force: Bool = false) {
        let next = page.fingerprint
        guard force || next != fingerprint || page.id != self.page?.id
                || page.topInset != self.page?.topInset else {
            self.page = page
            return
        }
        if self.page != nil {
            if self.page?.id == page.id { cancelActivePresses() }
            else { reset() }
        }
        fingerprint = next
        self.page = page
        solvedSize = .zero
        neutralLayout = KeyGridLayout()
        layout = KeyGridLayout()
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Re-solving on a size change only. Solving is arithmetic over the page,
        // and doing it per keystroke is the cost that used to make typing lag.
        guard bounds.size != solvedSize, let page else { return }
        // Rotation invalidates finger coordinates and the popup's source frame.
        // Cancel only the fingers; keep Shift/Caps state across the resize.
        if solvedSize != .zero { cancelActivePresses() }
        solvedSize = bounds.size
        neutralLayout = KeyGridPlacement.solve(page, in: bounds.size)
        layout = page.id == "letters" && hitPrediction != nil
            ? KeyGridPlacement.retarget(neutralLayout, probabilities: hitPrediction)
            : neutralLayout
        updateVariantPopup()
        updatePressPreview()
        logSolvedGeometry()
        updateKeypadControls()
        onGlassLayoutChanged?(glassSpecs)
        setNeedsDisplay()
    }

    /// Records the solved plates, so a render can be compared with the arithmetic
    /// that produced it instead of guessed at.
    ///
    /// This exists because the two disagreed silently for a while. The solver
    /// reported 33.4pt letter keys and the screen showed 29.8pt ones, and nothing
    /// said so: the code was correct by inspection, the unit tests were correct
    /// because they built their own page, and only measuring the actual render
    /// found that the row reaching the solver was not the row being drawn. One log
    /// line per solve turned that into a two-minute check.
    ///
    /// Solves happen on size change only, not per keystroke, so this is cheap. It
    /// records geometry and key counts, never what was typed.
    private func logSolvedGeometry() {
        guard let page else { return }
        var parts: [String] = ["page=\(page.id) size=\(Int(bounds.width))x\(Int(bounds.height))"]
        for (index, row) in layout.rows.enumerated() {
            let first = row.first?.plate
            let last = row.last?.plate
            let glyph = row.first(where: { $0.key.label?.isEmpty == false })?.plate
            parts.append("r\(index)n=\(row.count)"
                + " x=\(Int(first?.minX ?? -1))..\(Int(last?.maxX ?? -1))"
                + " w=\(String(format: "%.1f", first?.width ?? 0))"
                + " h=\(String(format: "%.1f", first?.height ?? 0))"
                + " y=\(String(format: "%.1f", first?.minY ?? 0))"
                + " r=\(String(format: "%.1f", row.first.map { cornerRadius(for: $0.key) } ?? 0))"
                + (glyph.map { " glyphCx=\(String(format: "%.1f", $0.midX))" } ?? ""))
        }
        PersistentLog.log(.keyboardGridGeometryProbe(details: parts.joined(separator: " | ")))
    }

    /// Drops any gesture in flight and clears the shift latches.
    ///
    /// Called when the keyboard leaves this page. A press that is still being
    /// tracked when the page changes is the shape of bug where a character is
    /// committed to a field the user has already left.
    func reset() {
        cancelActivePresses()
        shiftLatched = false
        isCapsLocked = false
        setNeedsDisplay()
    }

    private func cancelActivePresses() {
        keypadVoice.cancelInteraction()
        keypadLetters.cancelInteraction()
        for press in presses.values {
            press.popupWork?.cancel()
        }
        presses.removeAll()
        popupOwner = nil
        previewOwner = nil
        updatePressPreview()
        updateVariantPopup()
        if repeatingKey != nil { delegate?.keyGridDidEndRepeat(self) }
        repeatingKey = nil
        setNeedsDisplay()
    }

    /// Appearance preferences never require a new page or a geometry solve.
    func refreshAppearance() {
        updateKeypadControls()
        onGlassLayoutChanged?(glassSpecs)
        onCommandFacesChanged?(commandSpecs)
        updateVariantPopup()
        updatePressPreview(force: true)
        setNeedsDisplay()
    }

    /// A new prior only changes the target map; active fingers retain their
    /// press identity and the visible plates are never re-solved or redrawn.
    func updateHitPrediction(_ prediction: NextCharacterProbabilities?) {
        let next = page?.id == "letters" ? prediction : nil
        guard next != hitPrediction else { return }
        hitPrediction = next
        guard solvedSize == bounds.size, !neutralLayout.placed.isEmpty else { return }
        layout = next == nil ? neutralLayout
            : KeyGridPlacement.retarget(neutralLayout, probabilities: next)
    }

    // MARK: - Drawing

    /// A quiet route back to voice when a numeric host has no shared bottom bar.
    /// It uses the blank part of Delete's wide cell, keeping digit plates intact.
    private func updateKeypadControls() {
        keypadVoice.isHidden = true
        keypadLetters.isHidden = true
        guard page?.id == "numberPad" else { return }
        if let letters = layout.placed.first(where: { $0.key.id == "pad-letters" }) {
            let rect = visualPlate(for: letters)
            keypadLetters.frame = letters.target
            keypadLetters.holdDuration = KeyboardDeletion.holdRecognitionDuration
            let face = keypadLetters.keyboardFace
            face.autoresizingMask = []
            face.frame = rect.offsetBy(dx: -letters.target.minX, dy: -letters.target.minY)
            face.configure(text: "ABC", visualSize: rect.size,
                holdSymbol: KeyboardInteractionPreferences.topBarEnabled ? nil : "mic.fill")
            keypadLetters.isHidden = false
        }
        guard !KeyboardInteractionPreferences.topBarEnabled,
              let delete = layout.placed.first(where: { $0.key.id == "pad-delete" }) else { return }
        let face = visualPlate(for: delete)
        let room = face.minX - KeyGridPlacement.keySpacing - delete.target.minX
        let height = min(44, delete.target.height)
        guard room >= 44, height >= 28 else { return }
        keypadVoice.frame = CGRect(x: delete.target.minX + (room - 44) / 2,
                                  y: delete.target.midY - height / 2, width: 44, height: height)
        keypadVoice.keyboardFace.configure(symbol: "mic.fill", role: .accessory)
        keypadVoice.isHidden = false
    }

    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        updatePressPreview()
        let specs = commandSpecs
        guard specs != publishedCommandSpecs else { return }
        publishedCommandSpecs = specs
        onCommandFacesChanged?(specs)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let held = heldPositions()
        for row in layout.rows {
            for item in row {
                let isPressed = held.contains(PlacedPosition(row: item.row, column: item.column))
                drawPlate(item, pressed: isPressed, context: context)
            }
        }
    }

    private struct PlacedPosition: Hashable {
        let row: Int
        let column: Int
    }

    private func heldPositions() -> Set<PlacedPosition> {
        Set(presses.values.map { PlacedPosition(row: $0.row, column: $0.column) })
    }

    /// A plate that should be backed by real material.
    struct GlassSpec: Equatable {
        let rect: CGRect
        let radius: CGFloat
    }

    struct CommandSpec: Equatable {
        let rect: CGRect
        let systemName: String?
        let text: String?
        let pressed: Bool
    }

    /// Told every time the set of glass plates changes, so the host can realise the
    /// material in a sibling layer. The grid cannot host it itself: a
    /// `UIVisualEffectView` is a subview, and subviews draw *above* the receiver's
    /// own `draw(_:)`, so the glyphs would be covered.
    ///
    /// The host puts that layer below the grid. That also keeps the material out of
    /// the touch path — on iOS 26 a glass layer can win the hit test on its own,
    /// which is how Liquid Glass keys became untappable before.
    var onGlassLayoutChanged: (([GlassSpec]) -> Void)?
    var onCommandFacesChanged: (([CommandSpec]) -> Void)?

    private var commandSpecs: [CommandSpec] {
        let held = heldPositions()
        return layout.rows.flatMap { row in
            row.compactMap { item in
                guard item.key.isCommand else { return nil }
                if item.key.id == "pad-letters", !keypadLetters.isHidden { return nil }
                if case .none = item.key.action { return nil }
                let systemName = item.key.id == "shift"
                    ? (shiftActive ? "shift.fill" : "shift")
                    : item.key.systemImage
                return CommandSpec(
                    rect: visualPlate(for: item),
                    systemName: systemName,
                    text: systemName == nil ? displayText(for: item.key) : nil,
                    pressed: held.contains(PlacedPosition(row: item.row, column: item.column))
                        || (item.key.id == "shift" && shiftTouch != nil)
                )
            }
        }
    }

    /// Every visible plate has a fallback below the sibling glass material.
    private var glassSpecs: [GlassSpec] {
        var specs: [GlassSpec] = []
        for row in layout.rows {
            for item in row {
                guard showsPlate(for: item.key),
                      !(item.key.isCommand && onCommandFacesChanged != nil) else { continue }
                specs.append(GlassSpec(rect: visualPlate(for: item),
                                       radius: cornerRadius(for: item.key)))
            }
        }
        return specs
    }

    /// The plate a key draws at: the shared command size for a command key, otherwise
    /// its hit plate.
    ///
    /// One rule, used by both the material and the fallback fill, so they cannot
    /// disagree about how big a key looks.
    private func visualPlate(for item: PlacedKey) -> CGRect {
        item.key.isCommand
            ? CommandKeyStyle.visualPlate(for: item.plate, surfaceWidth: bounds.width,
                                         neighborGap: KeyGridPlacement.keySpacing)
            : item.plate
    }

    /// Spacers have no face.
    private func showsPlate(for key: KeyGridKey) -> Bool {
        if case .none = key.action { return false }
        return true
    }

    private func cornerRadius(for key: KeyGridKey) -> CGFloat {
        key.isCommand ? KeyGridPlacement.commandCornerRadius : KeyboardChromeRole.keyCornerRadius
    }

    private var usesLiveMaterial: Bool {
        // Glass belongs to the shared background; key faces stay quiet and flat.
        return false
    }

    private func drawPlate(_ item: PlacedKey, pressed: Bool, context: CGContext) {
        if case .none = item.key.action { return }
        if item.key.id == "pad-letters", !keypadLetters.isHidden { return }
        if item.key.isCommand, onCommandFacesChanged != nil { return }
        guard showsPlate(for: item.key) else {
            drawLabel(for: item.key, in: item.plate, pressed: pressed)
            return
        }
        let radius = cornerRadius(for: item.key)
        if item.key.isCommand {
            // The shared command treatment, so a command key on this grid and one in
            // the bottom bar or the emoji page are the same button.
            //
            // `CommandKeyFace` expresses the shared scale and opacity in SwiftUI.
            // opacity. Core Graphics cannot dim a sibling material view — it belongs
            // to another view — so the same numbers are spent here as a scaled plate
            // and a lightening wash inside it. Fading a dark glass plate over a dark
            // keyboard reads as a lightening, which is what the wash does.
            //
            // The wash is drawn only while held. Painting it unconditionally would
            // put an 18% white film over every command key at rest.
            //
            // The plate is drawn at the shared command size, centred on the hit area, so
            // it is the same rectangle the emoji delete draws. The hit area is untouched.
            let plate = CommandKeyStyle.pressedPlate(
                visualPlate(for: item), pressed: pressed
            )
            // A shift that is changing the next character is *not* lit on the plate.
            //
            // It was, and the plate went white, which is the single most obvious thing on
            // the keyboard and not what the platform does. The system keyboard keeps
            // this plate exactly as it was and changes only the arrow: hollow at rest,
            // solid while shift is engaged. The state is carried by the icon, because
            // that is the part the platform varies, and a white plate reads as a
            // different key rather than a different state of this one.
            let lit = false
            if !usesLiveMaterial {
                fill(plate, radius: radius,
                     color: plateColor(pressed: pressed, isLit: lit,
                                       isLetter: item.key.isInvisiblePlate), in: context)
            } else if pressed || lit {
                // A wash, not a fill: the sibling glass layer is the face, and this
                // only has to change how it reads. Held it is the press wash; lit it
                // is lighter, because it is a state rather than a touch.
                fill(plate, radius: radius,
                     color: UIColor.label.withAlphaComponent(
                        pressed ? CommandKeyStyle.pressWashAlpha
                                : CommandKeyStyle.litWashAlpha),
                     in: context)
            }
        } else if !usesLiveMaterial {
            fill(item.plate, radius: radius,
                 color: plateColor(pressed: pressed, isLetter: true),
                 in: context)
        } else if pressed {
            fill(item.plate, radius: radius,
                 color: UIColor.label.withAlphaComponent(0.10), in: context)
        }
        let labelPlate = item.key.isCommand
            ? CommandKeyStyle.pressedPlate(visualPlate(for: item), pressed: pressed)
            : item.plate
        drawLabel(for: item.key, in: labelPlate, pressed: pressed)
    }

    private func fill(_ rect: CGRect, radius: CGFloat, color: UIColor, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        context.fillPath()
        context.restoreGState()
    }

    /// Plate fill. The material preference is visual only and is resolved here, so
    /// it can never influence which key is pressed.
    ///
    /// Solid keys and commands resolve the same semantic roles as native/SwiftUI faces.
    private func plateColor(
        pressed: Bool,
        isLit: Bool = false,
        isLetter: Bool = false
    ) -> UIColor {
        if pressed {
            return isLetter
                ? UIColor.label.withAlphaComponent(0.10)
                : UIColor.label.withAlphaComponent(0.13)
        }
        // Lit outranks the material fill: an engaged shift has to read as engaged
        // whether or not the glass preference is on.
        if isLit {
            return UIColor.label.withAlphaComponent(CommandKeyStyle.litWashAlpha)
        }
        if usesLiveMaterial {
            return UIColor.secondarySystemFill.withAlphaComponent(0.5)
        }
        return (isLetter ? KeyboardChromeRole.input : .control)
            .solidFill(increasedContrast: UIAccessibility.isDarkerSystemColorsEnabled || UIAccessibility.isReduceTransparencyEnabled)
    }

    private func drawLabel(for key: KeyGridKey, in plate: CGRect, pressed: Bool) {
        // A command key dims by the shared amount, so its glyph fades with its plate.
        // Letter keys keep their own lighter dim: they have no plate to darken, so the
        // glyph is the only thing that can react.
        let dim = key.isCommand
            ? CommandKeyStyle.pressOpacity
            : 0.55
        let color = UIColor.label.withAlphaComponent(pressed ? dim : 1)
        // The period key carries a comma hint beneath its dot, as the legacy
        // control did, so punctuation was reachable without a second key.
        if key.id == "bar-period" {
            drawPeriodKey(in: plate, color: color)
            return
        }
        // Shift is drawn from the state it is actually in, not from a static glyph.
        //
        // It used to always draw `shift.fill` and switch to a `capslock.fill` padlock
        // when locked. Both halves of that were wrong. A filled arrow at rest means
        // the resting state and the armed state look identical, so there is nothing
        // to see change when a tap lands — which is the whole feedback the key
        // exists to give. And the padlock is not the platform's caps indicator: the
        // system keyboard keeps the *same* solid arrow for one-shot and for caps
        // lock, and tells them apart by whether it stays lit after you type.
        //
        // So: hollow arrow at rest, solid arrow whenever the next character will be
        // capitalised. `shift` is the hollow variant of the same symbol.
        if key.id == "shift" {
            drawSymbol(shiftActive ? "shift.fill" : "shift",
                       in: plate, size: key.glyphSize, color: color)
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
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: KeyboardChromeRole.secondaryForeground,
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
        case .regular: return UIAccessibility.isBoldTextEnabled ? .semibold : .regular
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

    /// The character a key contributes, with shift applied.
    ///
    /// Applies to plain inserts as well as accent keys. The factory only builds a
    /// `.character` action for letters that *have* accents, so restricting the shift
    /// to that case left every other letter — most of QWERTY — stuck in lower case
    /// while caps was on, both on the plate and in the text that reached the field.
    private func shiftedText(_ text: String) -> String {
        guard shiftActive, text.count == 1 else { return text }
        return text.uppercased()
    }

    private func displayText(for key: KeyGridKey) -> String {
        switch key.action {
        case .character(let base, _):
            return shiftActive ? base.uppercased() : base
        case .insert(let text):
            return shiftedText(text)
        default:
            return key.resolvedLabel
        }
    }

    private func updatePressPreview(force: Bool = false) {
        guard let previewOwner, let press = presses[previewOwner],
              !press.popupVisible, let text = press.previewText,
              let item = itemAt(row: press.row, column: press.column) else {
            previewPopupHost?.view.isHidden = true
            previewPopupIdentity = nil
            return
        }
        guard force || previewPopupIdentity != previewOwner else { return }
        let session = KeyPreviewSession(
            text: text, sourceFrame: item.plate,
            popupFrame: KeyPressPreviewHost.frame(for: item.plate, in: bounds.size)
        )
        let content = KeyPressPreviewHost(session: .constant(session))
        // Retain one host across key presses instead of allocating one per key.
        if let previewPopupHost {
            previewPopupHost.rootView = content
            previewPopupHost.view.frame = bounds
            previewPopupHost.view.isHidden = false
            bringSubviewToFront(previewPopupHost.view)
        } else {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.isUserInteractionEnabled = false
            host.view.frame = bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            attachKeyboardVisualController(host, from: self)
            previewPopupHost = host
        }
        previewPopupIdentity = previewOwner
    }

    private func updateVariantPopup() {
        guard let owner = popupOwner,
              let press = presses[owner],
              press.popupVisible,
              press.variants.count > 1,
              let item = itemAt(row: press.row, column: press.column) else {
            detachKeyboardVisualController(variantPopupHost)
            variantPopupHost = nil
            return
        }
        let frame = KeyVariantPopup.frame(
            for: item.plate, optionCount: press.variants.count,
            isEmoji: false, in: bounds.size
        )
        let popup = KeyVariantPopup(
            options: press.variants, selectedIndex: press.selectedVariant, isEmoji: false
        )
        if let variantPopupHost {
            variantPopupHost.rootView = popup
            variantPopupHost.view.frame = frame
        } else {
            let host = UIHostingController(rootView: popup)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.frame = frame
            host.view.accessibilityIdentifier = "key-variant-selector"
            attachKeyboardVisualController(host, from: self)
            variantPopupHost = host
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let point = touch.location(in: self)
            guard let item = layout.key(at: point) else { continue }
            let identity = ObjectIdentifier(touch)
            commitPendingCharacter()
            let action = item.key.action

            switch action {
            case .shift:
                // Nothing is latched on press. The decision belongs to the release,
                // because a double tap can only be recognised once the first one has
                // finished. Latching here is what made the second tap a no-op.
                shiftTouch = identity
                HapticFeedback.playInputClick()
                setNeedsDisplay()

            case .deleteRepeating:
                HapticFeedback.playInputClick()
                delegate?.keyGrid(self, perform: .delete, key: item.key)
                delegate?.keyGridDidBeginRepeat(self, key: item.key)
                repeatingKey = item.key
                presses[identity] = Press(
                    key: item.key, row: item.row, column: item.column,
                    previewText: nil,
                    waitsForRelease: false, variants: [],
                    popupVisible: false, selectedVariant: 0, popupWork: nil
                )

            case .insert(let text):
                // Inserted on press, with the shift applied. This is the branch
                // that carries most of the alphabet: the factory only builds a
                // `.character` action for letters that have accents, so without
                // handling shift here most keys typed lower case while caps was on.
                HapticFeedback.playInputClick()
                let inserted = shiftedText(text)
                presses[identity] = Press(
                    key: item.key, row: item.row, column: item.column,
                    previewText: text.count == 1 && !item.key.isCommand ? inserted : nil,
                    waitsForRelease: false, variants: [],
                    popupVisible: false, selectedVariant: 0, popupWork: nil
                )
                if text.count == 1 && !item.key.isCommand { previewOwner = identity }
                delegate?.keyGrid(self, perform: .insert(inserted), key: item.key)
                consumeOneShotShift()

            case .character(let base, let variants):
                HapticFeedback.playInputClick()
                if variants.count > 1 {
                    let ownsPopup = popupOwner == nil
                    if ownsPopup { popupOwner = identity }
                    var press = Press(
                        key: item.key, row: item.row, column: item.column,
                        previewText: shiftedText(base),
                        waitsForRelease: true, variants: variants.map(shiftedText),
                        popupVisible: false, selectedVariant: 0, popupWork: nil
                    )
                    if ownsPopup {
                        let work = KeyboardHoldSession()
                        work.begin(after: KeyboardDeletion.holdRecognitionDuration) { [weak self] in
                            self?.revealPopup(for: identity)
                        }
                        press.popupWork = work
                    }
                    presses[identity] = press
                    previewOwner = identity
                } else {
                    presses[identity] = Press(
                        key: item.key, row: item.row, column: item.column,
                        previewText: shiftedText(base),
                        waitsForRelease: false, variants: [],
                        popupVisible: false, selectedVariant: 0, popupWork: nil
                    )
                    previewOwner = identity
                    commit(shiftedText(base))
                }

            default:
                HapticFeedback.playInputClick()
                presses[identity] = Press(
                    key: item.key, row: item.row, column: item.column,
                    previewText: nil,
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
            let frame = KeyVariantPopup.frame(
                for: item.plate, optionCount: press.variants.count,
                isEmoji: false, in: bounds.size
            )
            let index = KeyVariantPopup.selectedIndex(
                at: touch.location(in: self), popupFrame: frame,
                optionCount: press.variants.count
            )
            guard index != press.selectedVariant else { continue }
            press.selectedVariant = index
            presses[identity] = press
            HapticFeedback.variantHighlightChanged()
            updateVariantPopup()
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
            // Shift is handled before the press table, because it is the one key
            // that is not stored there.
            if shiftTouch == identity {
                shiftTouch = nil
                if !cancelled { resolveShiftTap() }
                setNeedsDisplay()
                continue
            }
            guard let press = presses.removeValue(forKey: identity) else { continue }
            if previewOwner == identity { previewOwner = nil }
            press.popupWork?.cancel()
            if popupOwner == identity {
                popupOwner = nil
                updateVariantPopup()
            }
            if repeatingKey?.id == press.key.id {
                repeatingKey = nil
                delegate?.keyGridDidEndRepeat(self)
            }
            if cancelled { continue }
            switch press.key.action {
            case .character(let base, _):
                guard press.waitsForRelease else { continue }
                if press.popupVisible, press.variants.indices.contains(press.selectedVariant) {
                    commit(press.variants[press.selectedVariant])
                } else {
                    commit(press.previewText ?? shiftedText(base))
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

    private func revealPopup(for identity: ObjectIdentifier) {
        guard popupOwner == identity, var press = presses[identity], press.waitsForRelease else { return }
        press.popupVisible = true
        press.popupWork = nil
        presses[identity] = press
        HapticFeedback.variantPopupPresented()
        updateVariantPopup()
        setNeedsDisplay()
    }

    /// Settle an earlier accent key before the next key or bottom-bar action.
    /// Otherwise overlapping A-down, S-down, A-up inserts "sa". Mark it committed
    /// before calling the delegate, whose proxy route also calls this method.
    func commitPendingCharacter() {
        for (identity, var press) in presses where press.waitsForRelease {
            let text = press.popupVisible && press.variants.indices.contains(press.selectedVariant)
                ? press.variants[press.selectedVariant] : press.previewText
            press.waitsForRelease = false
            press.popupWork?.cancel()
            press.popupWork = nil
            press.popupVisible = false
            presses[identity] = press
            if popupOwner == identity { popupOwner = nil }
            if let text { commit(text) }
        }
        updateVariantPopup()
    }

    /// Character casing was captured when its finger pressed the key.
    private func commit(_ text: String) {
        delegate?.keyGrid(self, perform: .insert(text), key: KeyGridKey(id: "", action: .none))
        // Shift applies to one character. Leaving it latched is how a forgotten
        // shift turns a whole word uppercase. Caps lock is not consumed.
        consumeOneShotShift()
    }
}
