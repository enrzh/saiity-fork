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

/// One key's plate of Liquid Glass, drawn by SwiftUI.
///
/// `UIGlassEffect` in a bare `UIVisualEffectView` renders flat — measured about 20
/// luma lighter than the SwiftUI bar and uniform across the plate, with none of the
/// variation that reads as glass. So the plate is hosted from SwiftUI and drawn with
/// `glassEffect`, the same call the emoji page's delete and the bottom bar make.
///
/// Hosting rather than calling `UIGlassEffect` directly is the whole point: the two
/// renderers do not produce the same material, and the difference is visible.
private final class GlassPlateView: UIView {
    let host = UIHostingController(rootView: GlassPlate(radius: 0))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(host.view)
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // The glass is the only thing this view draws, and it must not take touches:
        // the grid below owns those.
        host.view.isUserInteractionEnabled = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not implemented") }

    /// Sets the corner radius and repaints the glass.
    func setRadius(_ radius: CGFloat) {
        host.rootView.radius = radius
        // The hosting view's layer rounds the glass to the plate's shape.
        layer.cornerCurve = .continuous
        layer.cornerRadius = radius
        clipsToBounds = true
    }
}

/// The SwiftUI side of a glass plate: a clear fill with the material over it.
private struct GlassPlate: View {
    var radius: CGFloat

    var body: some View {
        // `glassEffect` is iOS 26 and later. Below that there is no material to host,
        // and a clear fill is the honest fallback: the plate simply has no glass.
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }
}

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
    /// One glass plate view per spec, reconciled against the grid's layout.
    private var glassViews: [GlassPlateView] = []

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
            let view = GlassPlateView()
            view.host.view.backgroundColor = .clear
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
                view.setRadius(spec.radius)
            }
        }
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
        bottomBarHeight: CGFloat,
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
        let lane = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)
            + CGFloat(VoiceOnlyKeyboardPolicy.spacebarHeight)
            + CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
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
