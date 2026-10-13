import UIKit
import SwiftUI
import CoreGraphics
import SyllivraKernel

/// Key identity is geometry; interaction identity belongs to one finger only.
struct KeyGridPress {
    let keyID: String
    let id = UUID().uuidString
}

/// Reports what a `KeyGridTouchOwner` sees. One gesture, one key, one callback.
protocol KeyGridTouchOwnerDelegate: AnyObject {
    /// A finger went down on `keyID`, the key resolved from geometry.
    func keyGrid(_ owner: KeyGridTouchOwner, didPress keyID: String, at point: CGPoint)
    /// A finger that began on `keyID` moved. Used for accent drag and space cursor.
    func keyGrid(_ owner: KeyGridTouchOwner, didMove keyID: String, to point: CGPoint)
    /// A finger that began on `keyID` lifted, or was taken away.
    func keyGrid(_ owner: KeyGridTouchOwner, didRelease keyID: String, cancelled: Bool)
}

/// The touch owner for a grid of keys.
///
/// This is the reusable extraction of the emoji page's proven pattern, and it is
/// the same pattern the letter, number and symbol grids should all use.
///
/// ## Why a bare UIKit view and not a SwiftUI `UIViewRepresentable`
///
/// The emoji page is reliable because its touch owner is a real view in a real
/// UIKit hierarchy: the cell's `hitTest` claims its whole area, so UIKit routes
/// to it natively and nothing has to opt in. A `UIViewRepresentable` is different
/// — SwiftUI decides whether to route a touch into it, and that decision depends
/// on the SwiftUI content shape around it. Two letter-grid builds were lost to
/// that: one had no `contentShape` and was never consulted at all, the next still
/// was not. Putting this view directly into the controller's UIKit hierarchy, over
/// the hosting view, removes the SwiftUI decision from the path entirely.
///
/// ## Why one view for the whole grid
///
/// The earlier design gave every key its own control — roughly thirty views on the
/// letter page. Any SwiftUI state change (a key preview, the shift page, a
/// prediction update) runs `updateUIView` across all thirty and may destroy and
/// recreate any of them. A control that has left the hierarchy is sent neither
/// `touchesEnded` nor `touchesCancelled`, so the character is silently lost. That
/// is why the keyboard only failed when typing quickly: the slower the typing,
/// the more likely each gesture finished before the next rebuild. One view cannot
/// be torn down per key, because there is no per key.
///
/// ## Gesture policy
///
/// Mirrors the emoji page: gestures fail immediately rather than waiting, so
/// nothing can sit on a tap and cancel it halfway through.
final class KeyGridTouchOwner: UIView {
    weak var delegate: KeyGridTouchOwnerDelegate?

    /// Hit rectangles by row, in this view's coordinate space.
    var rows: [[CGRect]] = []
    /// Stable key identity for each rectangle, parallel to `rows`.
    ///
    /// Rectangles and identities are assigned together by `setGeometry`, so they
    /// cannot drift out of step. A mismatch would resolve a position to the wrong
    /// key's identity and commit the wrong character.
    private var keyIDs: [[String]] = []

    /// One in-flight touch and the key it belongs to.
    ///
    /// Keyed by touch identity, never by key: two fingers on two keys are two
    /// gestures, and tracking by key would let the second overwrite the first.
    private struct ActiveTouch {
        let press: KeyGridPress
        let handlers: KeyGridHandlers
        let onMove: ((KeyGridPress, CGPoint) -> Void)?
        let onRelease: ((KeyGridPress, Bool) -> Void)?
    }
    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]
    fileprivate var activeHandlers: KeyGridHandlers?

    /// Session totals, reported once when the keyboard goes away.
    ///
    /// Per-touch logging cost roughly twenty file writes per keystroke and was a
    /// large part of why typing felt chunky. Counting instead of tracing keeps the
    /// hot path to two integer increments and still answers the question that
    /// matters: did touches reach the keyboard at all, and did every one of them
    /// come back?
    private(set) var pressCount = 0
    private(set) var releaseCount = 0
    private(set) var stillHeldAtDisappear = 0
    /// A one-line summary of what this owner saw, for the controller to log.
    func sessionSummary() -> String {
        "presses=\(pressCount) releases=\(releaseCount) held=\(activeTouches.count)"
    }

    /// Rectangles owned by a dedicated control instead, such as delete and shift.
    /// The owner reports itself as not containing them, so UIKit routes those
    /// touches to the control that actually owns them.
    var excludedRects: [CGRect] = []

    /// The area this owner claims, in its own coordinates.
    ///
    /// The owner is mounted across the whole keyboard so a layout change can never
    /// leave it out of position, but it must not claim the bottom bar: space,
    /// return and the emoji key live there and belong to SwiftUI. `nil` means the
    /// grid is not mounted and the owner claims nothing.
    var claimsRect: CGRect?

    /// Installed by `KeyGridTouchBus`; kept separate from `delegate` so a surface
    /// can hand over closures without the owner holding a strong reference back.
    var onGesture: ((Gesture, KeyGridPress, CGPoint, Bool) -> Void)?

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
        // Many fingers at once, and never exclusively: one finger per key.
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isAccessibilityElement = false
    }

    /// Installs geometry and identities as one unit.
    ///
    /// `plates` was the tie-breaker for overlapping targets and is gone: the
    /// targets are now contiguous tiles, so exactly one contains any point and
    /// there is nothing to arbitrate.
    func setGeometry(rows: [[CGRect]], keyIDs: [[String]]) {
        self.rows = rows
        self.keyIDs = keyIDs
    }

    /// Claims the entire grid, including gaps and blank space between keys.
    ///
    /// A point in a gap must still resolve to a key, or a tap there is silently
    /// dropped. The emoji cell does the same thing by returning itself for
    /// anything inside its bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.contains(point) else { return false }
        guard let claimsRect else { return false }
        guard claimsRect.contains(point) else { return false }
        return !excludedRects.contains { $0.contains(point) }
            && keyID(at: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let keyID = keyID(at: point) else {
                // Anomaly only: the owner claimed the area but no key is under the
                // finger, which means the published geometry has drifted from the
                // surface. Rare, and cheap to record because it should not happen.
                let claim = claimsRect.map {
                    "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width))x\(Int($0.height))"
                } ?? "nil"
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyGridTouch",
                    instanceID: "press",
                    action: "unresolved",
                    details: "point=(\(Int(point.x)),\(Int(point.y))) rows=\(rows.count) claims=\(claim)"
                ))
                continue
            }
            guard let handlers = activeHandlers else {
                KeyGridTouchBus.reportOrphanedGesture()
                continue
            }
            pressCount += 1
            let press = KeyGridPress(keyID: keyID)
            activeTouches[ObjectIdentifier(touch)] = ActiveTouch(
                press: press, handlers: handlers,
                onMove: handlers.onMove, onRelease: handlers.onRelease
            )
            onGesture?(.press, press, surfacePoint(from: point), false)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let active = activeTouches[ObjectIdentifier(touch)] else { continue }
            guard active.handlers === activeHandlers else { continue }
            active.onMove?(active.press, surfacePoint(from: touch.location(in: self)))
        }
    }

    /// Converts a point from the owner's space into the surface's own space.
    ///
    /// Geometry is published in the owner's coordinates, which are the input view's
    /// — origin at the top-left of the whole keyboard. A surface's key frames are
    /// relative to the surface, and `KeyboardRootView` places that at
    /// `layout.surfaceFrame`, below the suggestion lane. Handing a surface an
    /// input-view point while it compares against surface-relative frames silently
    /// shifted every position by the lane height.
    ///
    /// That was invisible for plain keys, which only commit, and broke exactly the
    /// features that read the position: accent drag-selection. On the symbol page
    /// the popup appeared and then committed nothing, because the option under the
    /// finger was calculated in the wrong space.
    private func surfacePoint(from point: CGPoint) -> CGPoint {
        guard let claimsRect else { return point }
        return CGPoint(x: point.x - claimsRect.origin.x, y: point.y - claimsRect.origin.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A gesture recognizer elsewhere in the hierarchy can take a touch away
        // mid-press. For a key grid there is no gesture that should ever do that,
        // so a cancelled touch is reported as a release: the dictionary guarantees
        // exactly one report per touch, so this cannot double-insert.
        finish(touches, cancelled: false)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            guard let active = activeTouches.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            releaseCount += 1
            let stale = active.handlers !== activeHandlers
            // Only the anomaly is traced. A release that arrives after the surface
            // re-published is reported as cancelled and the character is dropped,
            // and from the outside that is indistinguishable from a lost touch.
            // Logging every release would cost a file write per keystroke.
            if stale || cancelled {
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyGridTouch",
                    instanceID: "release",
                    action: "droppedRelease",
                    details: "key=\(active.press.keyID) stale=\(stale) cancelled=\(cancelled)"
                ))
            }
            active.onRelease?(active.press, cancelled || stale)
        }
    }

    private func keyID(at point: CGPoint) -> String? {
        let hit = KeyboardKeyHitResolver.keyIndex(at: point, rows: rows)
            ?? nearestEdgeKey(at: point)
        guard let hit,
              keyIDs.indices.contains(hit.row),
              keyIDs[hit.row].indices.contains(hit.column) else { return nil }
        return keyIDs[hit.row][hit.column]
    }

    /// Only recover a near miss at a row edge. Interior gaps are tiled by the
    /// shared geometry, and dedicated keys must retain their own UIKit target.
    private func nearestEdgeKey(at point: CGPoint) -> (row: Int, column: Int)? {
        let limit: CGFloat = 10
        var best: (row: Int, column: Int, distance: CGFloat)?
        for (rowIndex, row) in rows.enumerated() where !row.isEmpty {
            for columnIndex in [0, row.count - 1] {
                let frame = row[columnIndex]
                guard !excludedRects.contains(where: { $0.intersects(frame) }),
                      point.y >= frame.minY, point.y < frame.maxY else { continue }
                let distance = max(frame.minX - point.x, point.x - frame.maxX, 0)
                if distance <= limit, distance < (best?.distance ?? .infinity) {
                    best = (rowIndex, columnIndex, distance)
                }
            }
        }
        return best.map { ($0.row, $0.column) }
    }

    /// True when no gesture is in flight. Lets a test assert the owner is not
    /// holding touches across a surface rebuild.
    var hasActiveTouches: Bool { !activeTouches.isEmpty }
}

/// The callbacks a key surface supplies to the shared owner.
///
/// Held by a class so a SwiftUI surface can keep one instance for its lifetime
/// and refresh the closures as its state changes, rather than re-registering an
/// owner on every re-render.
final class KeyGridHandlers {
    var onPress: ((KeyGridPress, CGPoint) -> Void)?
    var onMove: ((KeyGridPress, CGPoint) -> Void)?
    var onRelease: ((KeyGridPress, Bool) -> Void)?

    /// Replaces the callbacks in place.
    ///
    /// Surfaces call this on every render. The instance itself must stay stable,
    /// because the bus tracks ownership by its identity, but the closures must
    /// never be left pointing at a previous render's state. Activation is gated on
    /// geometry changing, so without this a grid that redrew for any other reason
    /// would keep dispatching through stale callbacks — which is how fast typing
    /// lost presses while slow typing worked.
    func refresh(
        onPress: @escaping (KeyGridPress, CGPoint) -> Void,
        onMove: @escaping (KeyGridPress, CGPoint) -> Void,
        onRelease: @escaping (KeyGridPress, Bool) -> Void
    ) {
        self.onPress = onPress
        self.onMove = onMove
        self.onRelease = onRelease
    }

    func fire(_ gesture: KeyGridTouchOwner.Gesture, keyID: KeyGridPress, point: CGPoint, cancelled: Bool) {
        switch gesture {
        case .press: onPress?(keyID, point)
        case .move: onMove?(keyID, point)
        case .release: onRelease?(keyID, cancelled)
        }
    }
}

/// The bridge between a SwiftUI key surface and a UIKit touch owner.
///
/// The owner is real UIKit mounted above the SwiftUI hosting view, so nothing has
/// to ask SwiftUI to route a touch into a representable. The letter grid tried
/// that three times and the owner was never consulted once, which presented as a
/// keyboard that rendered perfectly and ignored every tap.
enum KeyGridTouchBus {
    /// The mounted owner, or nil before the controller has attached it.
    private(set) static weak var owner: KeyGridTouchOwner?

    /// Retain the active registration until replacement or deactivation. SwiftUI
    /// creates these callbacks in `body`; its temporary view values are not a
    /// lifetime owner. A weak registration leaves live hit rectangles with no
    /// listener after a redraw (observed as `ownerOrphanedGesture` on device).
    private(set) static var handlers: KeyGridHandlers?

    /// Identifies which surface currently owns the grid.
    ///
    /// There is one owner and several surfaces, and they replace each other. SwiftUI
    /// can tear the outgoing surface down *after* its successor has published, so a
    /// surface leaving must not clear a grid that is already live. Ownership is
    /// therefore tracked by identity, and `deactivate(handlers:)` only clears when
    /// the caller is still the owner.
    private static var ownerToken: ObjectIdentifier?

    /// Installed by whichever view owns touches — see `KeyboardViewController`.
    static func attach(_ owner: KeyGridTouchOwner) {
        self.owner = owner
        // The handler must be looked up through `self.handlers` at gesture time,
        // never captured. `attach` runs while the controller is being built, long
        // before any surface has activated, so a `[weak handlers]` capture binds
        // nil permanently: touches resolved to a key and then went nowhere. That
        // presented as a keyboard that drew every key and did nothing with any of
        // them.
        owner.onGesture = { [weak owner] name, keyID, point, cancelled in
            guard let handlers = owner?.activeHandlers else {
                KeyGridTouchBus.reportOrphanedGesture()
                return
            }
            handlers.fire(name, keyID: keyID, point: point, cancelled: cancelled)
        }
    }

    /// Publishes a surface's grid and takes ownership for it.
    static func activate(geometry: KeyGridGeometry, handlers: KeyGridHandlers) {
        self.handlers = handlers
        ownerToken = ObjectIdentifier(handlers)
        owner?.activeHandlers = handlers
        owner?.setGeometry(rows: geometry.rows, keyIDs: geometry.keyIDs)
        owner?.excludedRects = geometry.excludedRects
        owner?.claimsRect = geometry.gridRect
    }

    /// Releases the grid, but only when `handlers` is still the owner.
    static func deactivate(handlers: KeyGridHandlers) {
        guard ownerToken == ObjectIdentifier(handlers) else { return }
        deactivate()
    }

    /// Called when a surface disappears, or when ownership is being reset.
    static func deactivate() {
        handlers = nil
        ownerToken = nil
        owner?.activeHandlers = nil
        owner?.setGeometry(rows: [], keyIDs: [])
        owner?.excludedRects = []
        owner?.claimsRect = nil
    }

    /// A gesture reached the owner but there is no surface listening.
    ///
    /// Logged rather than swallowed: this exact silence is what made four builds
    /// look like a dead keyboard instead of a wiring fault.
    static func reportOrphanedGesture() {
        PersistentLog.log(.diagnosticProbe(
            component: "TouchPath",
            instanceID: "6-owner",
            action: "ownerOrphanedGesture",
            details: "a gesture resolved to a key with no active surface handler"
        ))
    }
}

/// Geometry for one key grid: hit rectangles, their identities, the area the grid
/// occupies in the owner's coordinates, and the areas owned by something else.
///
/// `rows` are contiguous tiles spanning the whole grid, so exactly one contains
/// any point inside it. That is what makes `KeyboardKeyHitResolver` a plain
/// containment test with no tie-break.
struct KeyGridGeometry {
    var rows: [[CGRect]] = []
    var keyIDs: [[String]] = []
    var gridRect: CGRect = .zero
    var excludedRects: [CGRect] = []
}

/// Memoises a surface's derived key grid.
///
/// `body` runs on every state change — a press highlight, an accent popup, a
/// preview, the shift page — and each of those changes means rebuilding the whole
/// grid: policy geometry, row weights, frame solving, the pinned last row, hit
/// rectangles, and a signature string containing every rectangle. That work was
/// being redone on every keystroke, twice over, which is what made fast typing
/// lag while slow typing kept up.
///
/// A cache held by reference avoids that: a re-render for any reason *other* than
/// a geometry change reuses the previous result. This is deliberately not a
/// computed property, because a `View` is a value type and would recompute on each
/// evaluation.
final class KeyGridCache<Row> {
    /// Inputs the derivation actually depends on. Recomputed only when one changes.
    var key: String = "\u{0}:uninitialised"
    var rows: [Row] = []
    var geometry: KeyGridGeometry = KeyGridGeometry()

    /// Returns the cached rows when `key` matches, otherwise rebuilds and stores.
    @discardableResult
    func resolve(
        key: String,
        build: () -> (rows: [Row], geometry: KeyGridGeometry)
    ) -> [Row] {
        if self.key != key {
            let result = build()
            self.key = key
            self.rows = result.rows
            self.geometry = result.geometry
        }
        return rows
    }
}

extension View {
    /// Hands this surface's key grid to the shared UIKit touch owner.
    ///
    /// This is the reusable half of the component: a surface declares its geometry
    /// and its three callbacks, and everything about *owning* touches — the UIKit
    /// view, the hit testing, the coordinate translation, the registration
    /// lifetime — lives here and in `KeyGridTouchOwner`.
    ///
    /// `signature` must change whenever the geometry does, so the owner is
    /// refreshed on a real layout change rather than on every re-render.
    ///
    /// The modifier deliberately does **not** disable hit testing on the content.
    /// The owner sits above the hosting view and takes grid touches first, but it
    /// hands back the rectangles listed in `excludedRects`; keys that need native
    /// behaviour, such as delete's repeat and shift's page toggle, rely on that
    /// fallthrough to reach their own controls. Disabling touch handling across the
    /// grid would leave those keys with no owner at all.
    func keyGridInput(
        geometry: KeyGridGeometry,
        handlers: KeyGridHandlers,
        signature: String
    ) -> some View {
        modifier(KeyGridInputModifier(geometry: geometry, handlers: handlers, signature: signature))
    }
}

private struct KeyGridInputModifier: ViewModifier {
    let geometry: KeyGridGeometry
    let handlers: KeyGridHandlers
    let signature: String

    func body(content: Content) -> some View {
        content
            .onAppear { KeyGridTouchBus.activate(geometry: geometry, handlers: handlers) }
            .onChange(of: signature) { _, _ in
                KeyGridTouchBus.activate(geometry: geometry, handlers: handlers)
            }
            .onDisappear { KeyGridTouchBus.deactivate(handlers: handlers) }
    }
}

extension KeyGridTouchOwner {
    enum Gesture { case press, move, release }
}

/// SwiftUI bridge for `KeyGridTouchOwner`.
///
/// Prefer `PassthroughControlsView`'s built-in ownership via `KeyGridTouchBus` when
/// one is attached. This wrapper exists for surfaces that genuinely have no UIKit
/// owner available; on the letter grid the SwiftUI route was tried three times and
/// the owner was never consulted, because SwiftUI has to opt a representable into
/// hit-testing and never did.
struct KeyGridCapture: UIViewRepresentable {
    let geometry: KeyGridGeometry
    let onPress: (KeyGridPress, CGPoint) -> Void
    let onMove: (KeyGridPress, CGPoint) -> Void
    let onRelease: (KeyGridPress, Bool) -> Void

    func makeUIView(context: Context) -> KeyGridTouchOwner {
        let owner = KeyGridTouchOwner()
        apply(to: owner)
        return owner
    }

    func updateUIView(_ owner: KeyGridTouchOwner, context: Context) {
        // Updated in place, never recreated, so a gesture in flight survives any
        // SwiftUI state change elsewhere on the keyboard.
        apply(to: owner)
    }

    private func apply(to owner: KeyGridTouchOwner) {
        let handlers = owner.activeHandlers ?? KeyGridHandlers()
        handlers.refresh(onPress: onPress, onMove: onMove, onRelease: onRelease)
        owner.activeHandlers = handlers
        owner.setGeometry(rows: geometry.rows, keyIDs: geometry.keyIDs)
        owner.excludedRects = geometry.excludedRects
        owner.claimsRect = geometry.gridRect
        owner.onGesture = { name, keyID, point, cancelled in
            switch name {
            case .press: onPress(keyID, point)
            case .move: onMove(keyID, point)
            case .release: onRelease(keyID, cancelled)
            }
        }
    }
}
