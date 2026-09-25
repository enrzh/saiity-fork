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

import UIKit
import DictusCore

protocol NextKeyboardHostDelegate: AnyObject {
    func nextKeyboardHost(_ host: NextKeyboardHost, perform command: KeyboardCommand)
    func nextKeyboardHost(_ host: NextKeyboardHost, insert text: String)
    func nextKeyboardHostDidRequestLetters(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestSymbols(_ host: NextKeyboardHost)
    func nextKeyboardHostDidRequestEmoji(_ host: NextKeyboardHost)
    func nextKeyboardHost(_ host: NextKeyboardHost, didSelectSymbolPage id: String)
}

final class NextKeyboardHost: NSObject {

    weak var delegate: NextKeyboardHostDelegate?

    let gridView: KeyGridView

    /// Sits directly below the grid and carries the real key material.
    private let glassLayer: UIView
    /// One effect view per glass plate, reconciled against the grid's layout.
    private var glassViews: [UIVisualEffectView] = []

    /// Which symbol page is showing. The bar's toggle flips this.
    private var symbolPage: KeyGridPageFactory.Page = .symbolsNumbers

    // MARK: - Delete repeat
    //
    // The timing lives here rather than in the grid so there is one place that
    // knows how long a delete must be held before it repeats. Two constants, from
    // `KeyboardDeletion`, so the keyboard and the system agree.

    private var repeatTimer: Timer?
    private var isRepeatingDelete = false

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
    }

    deinit {
        repeatTimer?.invalidate()
    }

    // MARK: - Mounting

    /// Adds the grid to `container` and places it.
    ///
    /// The frame is in the container's own coordinates, which is what makes the
    /// geometry and the touch targets the same rectangles: the grid resolves a
    /// point in its own space and the plates were drawn in that same space.
    func mount(in container: UIView, frame: CGRect, page: Page) {
        if glassLayer.superview !== container {
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
        gridView.setNeedsLayout()
    }

    /// Keeps the grid above the material without letting either claim touches.
    private func gridLayerPosition() {
        // The controller raises the grid to 500 to sit above the SwiftUI host and
        // the voice overlay. The material follows just below it, and no higher: if
        // it rose above the SwiftUI chrome it would be visible over the accessory
        // lane, which has no plates of its own.
        glassLayer.layer.zPosition = gridView.layer.zPosition - 1
    }

    /// Reconciles the effect views against the grid's current plates.
    ///
    /// Reuses views by index so a re-solve does not churn the material, which is
    /// what makes the blur expensive.
    private func applyGlass(_ specs: [KeyGridView.GlassSpec]) {
        let wanted = KeyboardInteractionPreferences.liquidGlassEnabled
            && !UIAccessibility.isReduceTransparencyEnabled
        guard wanted, !specs.isEmpty else {
            glassViews.forEach { $0.removeFromSuperview() }
            glassViews.removeAll()
            return
        }
        while glassViews.count < specs.count {
            let view = UIVisualEffectView(effect: Self.keyMaterial())
            view.isUserInteractionEnabled = false
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            glassLayer.addSubview(view)
            glassViews.append(view)
        }
        while glassViews.count > specs.count {
            glassViews.removeLast().removeFromSuperview()
        }
        for (view, spec) in zip(glassViews, specs) {
            // No animation: a plate that slides or fades reads as a transition on
            // every re-solve, including the ones caused by an orientation change.
            UIView.performWithoutAnimation {
                view.frame = spec.rect
                view.layer.cornerRadius = spec.radius
            }
        }
    }

    /// The material the legacy `glassEffect(.regular)` resolves to.
    private static func keyMaterial() -> UIVisualEffect {
        if #available(iOS 26, *) {
            return UIGlassEffect()
        }
        return UIBlurEffect(style: .systemChromeMaterial)
    }

    func unmount() {
        // A gesture still in flight when the page goes away would otherwise commit
        // into a field the user has already left.
        gridView.reset()
        gridView.isHidden = true
        gridView.isUserInteractionEnabled = false
        gridView.removeFromSuperview()
        glassViews.forEach { $0.removeFromSuperview() }
        glassViews.removeAll()
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
            gridView.setPage(KeyGridPageFactory.letters())
        case .symbols:
            gridView.setPage(KeyGridPageFactory.symbols(symbolPage))
        case .numberPad(let style):
            gridView.setPage(KeyGridPageFactory.numberPad(style: style))
        }
    }

    // MARK: - Geometry

    /// The container rect the grid should occupy for a given surface.
    ///
    /// Derived from the shared page layout rather than hard-coded, so the new
    /// keyboard sits in the same place as the voice board's chrome and leaves the
    /// same space at the bottom.
    ///
    /// The letter page is inset from the top of the surface by
    /// `letterKeyboardHeaderHeight`. That band is not decoration: it is what keeps
    /// the rows at their 45pt height instead of letting them stretch to fill the
    /// surface, and its absence is most of why the rebuilt page read as too airy
    /// next to the legacy one. `letterKeyboardFrame` already carries the inset, so
    /// the grid reuses the policy's own frame rather than re-deriving it.
    ///
    /// The symbol and number pages take the whole surface, as they did before.
    static func gridFrame(
        for layout: VoiceOnlyKeyboardPolicy.Layout,
        surfaceHeight: CGFloat,
        bottomBarHeight: CGFloat,
        page: Page
    ) -> CGRect {
        if page == .letters {
            return layout.letterKeyboardFrame
        }
        let surface = layout.surfaceFrame
        let height = max(0, surface.height - bottomBarHeight)
        return CGRect(x: surface.minX, y: surface.minY, width: surface.width, height: height)
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

    // MARK: - Delete repeat

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        isRepeatingDelete = true
        // A pause before the first repeat, so a normal tap is never repeated.
        repeatTimer = Timer.scheduledTimer(
            withTimeInterval: KeyboardDeletion.repeatDelay,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(
                withTimeInterval: KeyboardDeletion.repeatInterval,
                repeats: true
            ) { [weak self] _ in
                guard let self, self.isRepeatingDelete else { return }
                self.delegate?.nextKeyboardHost(self, perform: .delete)
            }
        }
        if let repeatTimer {
            // Repeating while a finger is held in a menu, a popover or a scroll
            // view is the behaviour people expect, and `common` keeps it alive when
            // the touch is momentarily stationary.
            RunLoop.main.add(repeatTimer, forMode: .common)
        }
    }

    private func stopDeleteRepeat() {
        isRepeatingDelete = false
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
