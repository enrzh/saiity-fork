// DictusKeyboard/Next/NextKeyboardHost.swift
//
// Owns the new keyboard's grid and connects it to the text proxy.
//
// ## Why a host object at all
//
// The grid knows how to draw keys and resolve touches. It must not know how to
// insert text, which surface is showing, or when the keyboard is going away. Those
// are the controller's facts, and a stale keyboard controller is a real thing on
// iOS: it can be told to appear long after it has left the screen.
//
// So the host is a plain object the controller creates and destroys. It holds no
// globals, registers with nothing, and can be torn down mid-gesture without
// leaving state behind for the next instance to inherit. That is the structural
// difference from the shared touch bus this replaces, where a process-wide
// registry outlived the controller that filled it and any controller could revoke
// another's live input.

import SwiftUI
import UIKit
import DictusCore

/// One hosted material layer, with independent plates drawn at the grid's
/// resolved rectangles. The UIKit grid remains the only touch owner.
private struct GlassPlates: View {
    let pageID: String
    let specs: [KeyGridView.GlassSpec]
    let commands: [KeyGridView.CommandSpec]
    let liquidGlassEnabled: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if #available(iOS 26.0, *) {
                ForEach(specs.indices, id: \.self) { index in
                    let spec = specs[index]
                    Color.clear
                        .frame(width: spec.rect.width, height: spec.rect.height)
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: spec.radius, style: .continuous)
                        )
                        .position(x: spec.rect.midX, y: spec.rect.midY)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                }
            }
            ForEach(commands.indices, id: \.self) { index in
                let command = commands[index]
                Group {
                    if let systemName = command.systemName {
                        CommandKeyFace(systemName: systemName,
                                       plateWidth: command.rect.width,
                                       plateHeight: command.rect.height,
                                       isPressed: command.pressed)
                    } else if let label = command.text {
                        CommandKeyFace(text: label,
                                       plateWidth: command.rect.width,
                                       plateHeight: command.rect.height,
                                       isPressed: command.pressed)
                    }
                }
                .position(x: command.rect.midX, y: command.rect.midY)
            }
        }
        .id(pageID)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.keyboardLiquidGlassEnabled, liquidGlassEnabled)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

protocol NextKeyboardHostDelegate: AnyObject {
    func nextKeyboardHost(_ host: NextKeyboardHost, perform command: KeyboardCommand)
    func nextKeyboardHost(_ host: NextKeyboardHost, insert text: String)
    func nextKeyboardHostDidRequestLetters(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestSymbols(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestEmoji(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestDictation(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestWordDeletion(_ host: NextKeyboardHost)
    func nextKeyboardHost(_ host: NextKeyboardHost, didSelectSymbolPage id: String)
}

final class NextKeyboardHost: NSObject {

    weak var delegate: NextKeyboardHostDelegate?

    let gridView: KeyGridView

    /// Sits directly below the grid and carries the real key material.
    private let glassLayer: UIView
    private var glassHost: UIHostingController<GlassPlates>?
    private var glassSpecs: [KeyGridView.GlassSpec] = []
    private var commandSpecs: [KeyGridView.CommandSpec] = []
    private var commandRowCenterY: CGFloat?

    /// Which symbol page is showing. The bar's toggle flips this.
    private var symbolPage: KeyGridPageFactory.Page = .symbolsNumbers
    private var numberPadStyle: HostFieldPolicy.NumberPadStyle = .digits

    // MARK: - Delete repeat
    //
    // The timing lives here rather than in the grid so there is one place that
    // knows how long a delete must be held before it repeats. Two constants, from
    // `KeyboardDeletion`, so the keyboard and the system agree.

    private let deleteRepeat = KeyboardDeleteRepeatSession()

    // MARK: - Init

    override init() {
        gridView = KeyGridView(frame: .zero)
        glassLayer = UIView(frame: .zero)
        super.init()
        gridView.delegate = self
        // Translucent, and never opaque: the grid is a layer over the keyboard's
        // own background, not a replacement for it.
        gridView.backgroundColor = .clear
        gridView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // The material lives in its own layer rather than inside the grid, for two
        // reasons. A `UIVisualEffectView` is a subview, and subviews draw above the
        // grid's own `draw(_:)`, so glyphs drawn there would be covered. And on
        // iOS 26 a glass layer can win the hit test by itself, which is how Liquid
        // Glass keys went untappable before. Below the grid and non-interactive,
        // neither can happen.
        glassLayer.backgroundColor = .clear
        glassLayer.isUserInteractionEnabled = false
        glassLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gridView.onGlassLayoutChanged = { [weak self] specs in
            self?.applyGlass(specs)
        }
        gridView.onCommandFacesChanged = { [weak self] specs in
            self?.commandSpecs = specs
            self?.updateFaceHost()
        }
    }

    // MARK: - Mounting

    /// Adds the grid to `container` and places it.
    ///
    /// The frame is in the container's own coordinates, which is what makes the
    /// geometry and the touch targets the same rectangles: the grid resolves a
    /// point in its own space and the plates were drawn in that same space.
    func mount(in container: UIView, frame: CGRect, page: Page, commandRowCenterY: CGFloat? = nil) {
        self.commandRowCenterY = commandRowCenterY
        let materialWasDetached = glassLayer.superview !== container
        if materialWasDetached {
            glassLayer.removeFromSuperview()
            container.addSubview(glassLayer)
        }
        if gridView.superview !== container {
            gridView.removeFromSuperview()
            container.addSubview(gridView)
        }
        glassLayer.frame = frame
        gridLayerPosition()
        gridView.frame = frame
        show(page)
        gridView.layoutIfNeeded()
        // Returning from emoji can reuse the same solved page. Reattach its
        // material even when setPage correctly skips a redundant geometry solve.
        if materialWasDetached { gridView.refreshAppearance() }
    }

    /// Keeps the grid above the material without letting either claim touches.
    private func gridLayerPosition() {
        // The controller raises the grid to 500 to sit above the SwiftUI host and
        // the voice overlay. The material follows just below it, and no higher: if
        // it rose above the SwiftUI chrome it would be visible over the accessory
        // lane, which has no plates of its own.
        glassLayer.layer.zPosition = gridView.layer.zPosition - 1
    }

    /// Replaces the material layout without moving any visual plate or hit box.
    private func applyGlass(_ specs: [KeyGridView.GlassSpec]) {
        glassSpecs = []
        updateFaceHost()
    }

    private func updateFaceHost() {
        guard !glassSpecs.isEmpty || !commandSpecs.isEmpty else {
            detachKeyboardVisualController(glassHost)
            glassHost = nil
            return
        }
        let content = GlassPlates(pageID: gridView.page?.id ?? "",
                                 specs: glassSpecs, commands: commandSpecs,
                                 liquidGlassEnabled: KeyboardInteractionPreferences.liquidGlassEnabled)
        if let glassHost {
            glassHost.rootView = content
        } else {
            let host = UIHostingController(rootView: content)
            host.view.frame = glassLayer.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glassHost = host
        }
        if let glassHost { attachKeyboardVisualController(glassHost, from: glassLayer) }
    }

    func unmount() {
        guard gridView.superview != nil || glassLayer.superview != nil else { return }
        // A gesture still in flight when the page goes away would otherwise commit
        // into a field the user has already left.
        gridView.reset()
        gridView.isHidden = true
        gridView.isUserInteractionEnabled = false
        gridView.removeFromSuperview()
        detachKeyboardVisualController(glassHost)
        glassHost = nil
        glassSpecs = []
        commandSpecs = []
        commandRowCenterY = nil
        glassLayer.removeFromSuperview()
        stopDeleteRepeat()
    }

    /// The pages the host can show. Anything else — the voice board, recording,
    /// emoji — is not this object's business.
    enum Page: Equatable {
        case letters
        case symbols
        case numberPad(HostFieldPolicy.NumberPadStyle)
    }

    func show(_ page: Page) {
        gridView.isHidden = false
        gridView.isUserInteractionEnabled = true
        switch page {
        case .letters:
            gridView.setPage(aligned(KeyGridPageFactory.letters()))
        case .symbols:
            gridView.setPage(aligned(KeyGridPageFactory.symbols(symbolPage)))
        case .numberPad(let style):
            numberPadStyle = style
            gridView.setPage(KeyGridPageFactory.numberPad(style: style))
        }
        gridView.layoutIfNeeded()
    }

    /// A language or layout change must rebuild the active page, not only redraw
    /// its old keys. This is never called for visual-only preferences.
    func refreshKeyLayout() {
        guard let current = gridView.page else { return }
        let next: KeyGridPage
        switch current.id {
        case "letters":
            next = aligned(KeyGridPageFactory.letters())
        case "symbols1", "symbols2":
            next = aligned(KeyGridPageFactory.symbols(symbolPage))
        case "numberPad":
            next = KeyGridPageFactory.numberPad(style: numberPadStyle)
        default: return
        }
        guard next.fingerprint != current.fingerprint || next.topInset != current.topInset else { return }
        gridView.setPage(next, force: true)
        gridView.layoutIfNeeded()
    }

    private func aligned(_ page: KeyGridPage) -> KeyGridPage {
        guard let commandRowCenterY else { return page }
        return KeyGridPlacement.alignLastRow(
            page, in: gridView.bounds.size,
            centerY: commandRowCenterY - gridView.frame.minY
        )
    }

    /// Re-read shared appearance preferences for an already mounted page.
    func refreshAppearance() {
        gridView.refreshAppearance()
    }

    func updateHitPrediction(_ prediction: NextCharacterProbabilities?, enabled: Bool) {
        gridView.updateHitPrediction(prediction, enabled: enabled)
    }

    // MARK: - Geometry

    /// The container rect the grid should occupy for a given surface.
    ///
    /// The bottom bar is **not** the grid's to draw. `AuxiliaryBottomBar` is the
    /// one bottom bar this project has, and the emoji, symbol and legacy letter
    /// surfaces all use it. The rebuilt pages were carrying a second, hand-rolled
    /// bar, which is why the same keyboard showed two different bars depending on
    /// the page. So the grid is given only the rows' share of the surface and the
    /// bar lane is left to that shared component.
    ///
    /// The lane is the same three bands the emoji picker stacks below its content:
    /// `chromeCommandRowGap`, the bar itself, then `chromeBottomInset`.
    ///
    /// The letter page used to be inset from the top by `letterKeyboardHeaderHeight`,
    /// a 44pt band from the legacy layout. It is gone, and deliberately: the legacy
    /// band only made sense while rows were free to grow, because it was what stopped
    /// them stretching. Now that rows are capped at the platform's own 43pt key
    /// height, keeping the band as well squeezed them to 34.7pt — a third smaller
    /// than every key on the system keyboard. The space the band held now collects
    /// as ordinary slack above the block.
    static func gridFrame(
        for layout: VoiceOnlyKeyboardPolicy.Layout,
        surfaceHeight: CGFloat,
        page: Page
    ) -> CGRect {
        let surface = layout.surfaceFrame
        // The number pad takes the whole surface. It has no bottom bar — the system
        // pad does not have one either, it runs 1-9 and then a centred 0 with a
        // delete — so reserving the bar lane stole 54pt from four rows and left
        // every key 14pt short of the platform's.
        if case .numberPad = page {
            return surface
        }
        let lane = KeyGridPlacement.bottomBarLaneHeight
        let height = max(0, surface.height - lane)
        return CGRect(x: surface.minX, y: surface.minY,
                      width: surface.width, height: height)
    }
}

// MARK: - Grid delegate

extension NextKeyboardHost: KeyGridViewDelegate {

    func keyGrid(_ view: KeyGridView, perform action: KeyAction, key: KeyGridKey) {
        switch action {
        case .insert(let text):
            delegate?.nextKeyboardHost(self, insert: text)

        case .character(let base, _):
            // Reached only for a variant key released without choosing; the grid
            // commits those itself, so this is a safety net rather than the path.
            delegate?.nextKeyboardHost(self, insert: base)

        case .shift:
            // Handled inside the grid: it owns the latch and the caps-lock toggle,
            // because it draws the shifted glyphs.
            break

        case .delete, .deleteRepeating:
            delegate?.nextKeyboardHost(self, perform: .delete)

        case .space:
            delegate?.nextKeyboardHost(self, perform: .space)

        case .newline:
            delegate?.nextKeyboardHost(self, perform: .returnKey)

        case .symbols:
            delegate?.nextKeyboardHostDidRequestSymbols(self)

        case .letters:
            delegate?.nextKeyboardHostDidRequestLetters(self)

        case .emoji:
            delegate?.nextKeyboardHostDidRequestEmoji(self)

        case .page(let id):
            symbolPage = (symbolPage == .symbolsNumbers) ? .symbolsPunctuation : .symbolsNumbers
            delegate?.nextKeyboardHost(self, didSelectSymbolPage: id)
            show(.symbols)

        case .dismiss:
            break

        case .none:
            break
        }
    }

    func keyGridDidBeginRepeat(_ view: KeyGridView, key: KeyGridKey) {
        startDeleteRepeat()
    }

    func keyGridDidEndRepeat(_ view: KeyGridView) {
        stopDeleteRepeat()
    }

    func keyGridDidRequestDictation(_ view: KeyGridView) {
        delegate?.nextKeyboardHostDidRequestDictation(self)
    }

    // MARK: - Delete repeat

    private func startDeleteRepeat() {
        deleteRepeat.begin { [weak self] action in
            guard let self else { return }
            switch action {
            case .character: self.delegate?.nextKeyboardHost(self, perform: .delete)
            case .word: self.delegate?.nextKeyboardHostDidRequestWordDeletion(self)
            }
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeat.cancel()
    }
}
