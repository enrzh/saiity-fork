import SwiftUI
import UIKit
import Foundation
import DictusCore

struct SymbolKeyboardSurface: View {
    let page: KeyboardPage
    let surfaceLayout: VoiceOnlyKeyboardPolicy.Layout
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onTogglePage: (KeyboardPage) -> Void
    // Symbols use the dictation-board emoji control instead of an ABC control.
    let onClose: () -> Void
    let onBackToVoice: () -> Void
    let onEmoji: () -> Void
    let onKeyboard: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast
    @State private var variantSession: KeyVariantSession?
    @State private var previewSession: KeyPreviewSession?
    @State private var variantHoldToken: UUID?
    @State private var variantTouchOrigin: CGPoint?
    @State private var variantTouchCancelled = false
    @State private var activeVariantKeyID: String?
    @State private var nonPopupVariantTouchIDs: Set<String> = []
    /// Keys currently held, reported by the shared UIKit touch owner. Press
    /// feedback comes from the owner rather than from a control per key, so a key
    /// cannot lose its highlight by being rebuilt.
    @State private var pressedKeyIDs: [String: String] = [:]
    /// One handler instance for the surface's lifetime; see `refreshedGridHandlers`.
    @State private var gridHandlers = KeyGridHandlers()
    /// Memoises the derived grid; see `KeyGridCache`.
    @State private var gridCache = KeyGridCache<PositionedLiquidSymbolKey>()

    private let bottomBarHeight: CGFloat = 44
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)

    var body: some View {
        let _ = (onClose, onBackToVoice)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)
                // Only the size and the page change this grid's geometry. A press
                // highlight or an accent popup changes neither, so the whole grid
                // is reused instead of being rebuilt on the keystroke path.
                let cacheKey = "\(Int(gridSize.width))x\(Int(gridSize.height))"
                    + "-\(String(describing: page))"
                let frames = gridCache.resolve(key: cacheKey) {
                    let rows = positionedKeys(in: gridSize)
                    return (rows, ownedGridGeometry(frames: rows, bounds: gridSize))
                }
                let handlers = refreshedGridHandlers(frames: frames, bounds: gridSize)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { positionedKey in
                        symbolKey(
                            positionedKey.key,
                            keyID: positionedKey.id,
                            frame: positionedKey.frame,
                            visualFrame: positionedKey.visualFrame,
                            bounds: gridSize
                        )
                            .frame(width: positionedKey.frame.width, height: positionedKey.frame.height)
                            .position(x: positionedKey.frame.midX, y: positionedKey.frame.midY)
                    }
                    if let session = variantSession {
                        variantOverlay(session, in: gridSize)
                            .zIndex(20)
                    } else if previewSession != nil {
                        KeyPressPreviewHost(session: $previewSession)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .coordinateSpace(name: "symbolPage")
                // The grid is owned by the shared UIKit touch owner, the same one
                // the letter page uses. Keys are faces only; delete keeps its own
                // control for repeat and is excluded from the owner so those
                // touches fall through to it.
                .keyGridInput(
                    geometry: gridCache.geometry,
                    handlers: handlers,
                    signature: cacheKey
                )
                // Each key owns its touch; a second grid drag used to race
                // long-press selection and could delete again on release.
                .accessibilityElement(children: .contain)
            }
            Color.clear.frame(height: commandRowGap)
            AuxiliaryBottomBar(
                layout: surfaceLayout,
                numbersTitle: "123",
                onNumbers: {},
                onLetters: onKeyboard,
                onEmoji: onEmoji,
                spaceFrame: surfaceLayout.chromeWideSpaceFrame,
                returnFrame: surfaceLayout.chromeReturnFrame,
                onSpace: onSpace,
                onSpaceCursorBegan: onSpaceCursorBegan,
                onSpaceCursorMoved: onSpaceCursorMoved,
                onSpaceCursorEnded: onSpaceCursorEnded,
                onReturn: onReturn,
                showsNumbersControl: false
            )
            .frame(width: availableWidth, height: bottomBarHeight)
            Color.clear.frame(height: chromeBottomInset)
        }
        .frame(width: availableWidth, height: availableHeight)
        .onChange(of: page) { _, _ in
            variantSession = nil
            previewSession = nil
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
        .onDisappear {
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
    }

    private var rows: [[LiquidSymbolKey]] {
        switch page {
        case .symbols2:
            return KeyboardSymbolsLayout.symbols.enumerated().map { rowIndex, row in
                row.enumerated().map { columnIndex, key in
                    LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
                }
            }
        case .symbols1:
            return KeyboardSymbolsLayout.numbers.enumerated().map { rowIndex, row in
                row.enumerated().map { columnIndex, key in
                    LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
                }
            }
        default:
            return []
        }
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLiquidSymbolKey] {
        guard !rows.isEmpty else { return [] }
        let geometry = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(size.width))
        let edgeInset = geometry.keyGridInset
        let rowSpacing = geometry.keyRowSpacing
        let keySpacing = geometry.keySpacing
        let rowWeights = rows.map { row in row.map(\.width) }
        let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
            in: size.height,
            rowSpacing: rowSpacing
        )
        var frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
            for: rowWeights,
            in: size,
            spacing: keySpacing,
            inset: edgeInset,
            rowSpacing: rowSpacing,
            lastRowHeight: lastRowHeight,
            maxRowHeight: geometry.letterKeyHeight
        )
        if let row = frames.last, let first = row.first {
            frames[frames.count - 1] = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                itemCount: row.count,
                rowFrame: CGRect(
                    x: edgeInset,
                    y: first.minY,
                    width: max(0, size.width - edgeInset * 2),
                    height: first.height
                ),
                spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing),
                commandWidth: surfaceLayout.boardDeleteFrame.width
            )
        }
        let deleteFrame = CGRect(
            x: surfaceLayout.boardDeleteFrame.minX - surfaceLayout.surfaceFrame.minX,
            y: surfaceLayout.boardDeleteFrame.minY - surfaceLayout.surfaceFrame.minY,
            width: surfaceLayout.boardDeleteFrame.width,
            height: surfaceLayout.boardDeleteFrame.height
        )
        if let lastRow = frames.indices.last, rows.indices.contains(lastRow) {
            frames[lastRow] = frames[lastRow].map {
                CGRect(x: $0.minX, y: deleteFrame.minY, width: $0.width, height: deleteFrame.height)
            }
            for (index, key) in rows[lastRow].enumerated() {
                if case .delete = key.action, frames[lastRow].indices.contains(index) {
                    frames[lastRow][index] = deleteFrame
                }
            }
        }
        let hitFrames = KeyboardKeyHitGeometry.frames(for: frames)
        // The solved rows are not guaranteed to match the key rows, and reading past
        // the end of either array traps — which kills the keyboard extension
        // outright rather than merely failing to draw. Clamp the row count and zip
        // the columns so a degenerate container size degrades instead of crashing.
        let rowCount = min(rows.count, min(frames.count, hitFrames.count))
        guard rowCount > 0 else { return [] }
        return (0..<rowCount).flatMap { rowIndex -> [PositionedLiquidSymbolKey] in
            let row = rows[rowIndex]
            let rowHits = hitFrames[rowIndex]
            let rowPlates = frames[rowIndex]
            return zip(row.indices, zip(rowHits, rowPlates)).map { columnIndex, pair in
                PositionedLiquidSymbolKey(
                    key: row[columnIndex],
                    frame: pair.0,
                    visualFrame: pair.1
                )
            }
        }
    }

    private func key(at point: CGPoint, in frames: [PositionedLiquidSymbolKey]) -> LiquidSymbolKey? {
        if let direct = frames.first(where: {
            $0.frame.contains(point) && !$0.key.isSpacer
        }) {
            return direct.key
        }
        return nil
    }

    // MARK: - Shared UIKit touch owner

    /// A stable description of the grid, so the owner is refreshed when geometry
    /// actually changes rather than on every re-render.
    private func gridSignature(
        frames: [PositionedLiquidSymbolKey],
        bounds: CGSize
    ) -> String {
        let rects = frames
            .map { "\($0.id):\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height))" }
            .joined(separator: "|")
        return "\(Int(bounds.width))x\(Int(bounds.height))#\(rects)"
    }

    /// Geometry for the shared owner.
    ///
    /// `positionedKeys` works in surface-local coordinates, but the owner is
    /// mounted on the input view, whose origin is the top-left of the whole
    /// keyboard. `KeyboardRootView` places this surface at `layout.surfaceFrame`,
    /// below the suggestion lane and inset horizontally, so every rectangle is
    /// translated by that origin before it is published.
    private func ownedGridGeometry(
        frames: [PositionedLiquidSymbolKey],
        bounds: CGSize
    ) -> KeyGridGeometry {
        let origin = surfaceLayout.surfaceFrame.origin
        // `positionedKeys` already resolved each key's hit rectangle through
        // `KeyboardKeyHitGeometry`, so those rectangles are published as they are —
        // only translated into the owner's coordinate space. Grouping walks the
        // keys in the order they were produced and starts a new row whenever the
        // vertical origin changes, which keeps rectangles and identities parallel
        // without a second indexing scheme that could drift.
        var rows: [[CGRect]] = []
        var keyIDs: [[String]] = []
        var plates: [[CGRect]] = []
        var currentRects: [CGRect] = []
        var currentIDs: [String] = []
        var currentPlates: [CGRect] = []
        var previousMinY: CGFloat?
        for item in frames {
            let minY = item.frame.minY
            if let previousMinY, abs(previousMinY - minY) > 0.5, !currentRects.isEmpty {
                rows.append(currentRects)
                keyIDs.append(currentIDs)
                plates.append(currentPlates)
                currentRects = []
                currentIDs = []
                currentPlates = []
            }
            previousMinY = minY
            currentRects.append(item.frame.offsetBy(dx: origin.x, dy: origin.y))
            currentPlates.append(item.visualFrame.offsetBy(dx: origin.x, dy: origin.y))
            currentIDs.append(item.id)
        }
        if !currentRects.isEmpty {
            rows.append(currentRects)
            keyIDs.append(currentIDs)
            plates.append(currentPlates)
        }
        let gridRect = CGRect(origin: origin, size: bounds)
        return KeyGridGeometry(
            // Contiguous tiles spanning the whole grid: no dead band at the edges,
            // no overlap to arbitrate. Computed from the drawn plates, so the seams
            // still land in the gaps. Never used for layout.
            rows: KeyboardKeyHitGeometry.contiguousTiles(for: plates, in: gridRect),
            keyIDs: keyIDs,
            gridRect: gridRect,
            // Delete keeps its native repeat control.
            excludedRects: frames.compactMap { item in
                guard case .delete = item.key.action else { return nil }
                return item.frame.offsetBy(dx: origin.x, dy: origin.y)
            }
        )
    }

    /// Refreshes the surface's single handler instance in place and returns it.
    ///
    /// Stable identity, current closures: the bus tracks ownership by this object's
    /// identity, while activation is gated on geometry changing. Without refreshing
    /// on every render the grid would keep dispatching through callbacks captured
    /// from an earlier one.
    private func refreshedGridHandlers(
        frames: [PositionedLiquidSymbolKey],
        bounds: CGSize
    ) -> KeyGridHandlers {
        gridHandlers.refresh(
            onPress: { keyID, point in
                handleGridPress(keyID: keyID, point: point, frames: frames, bounds: bounds)
            },
            onMove: { keyID, point in
                handleGridMove(keyID: keyID, point: point, frames: frames)
            },
            onRelease: { keyID, cancelled in
                handleGridRelease(keyID: keyID, cancelled: cancelled, frames: frames)
            }
        )
        return gridHandlers
    }

    private func positioned(
        keyID: String,
        in frames: [PositionedLiquidSymbolKey]
    ) -> PositionedLiquidSymbolKey? {
        frames.first { $0.id == keyID && !$0.key.isSpacer }
    }

    private func handleGridPress(
        keyID press: KeyGridPress,
        point: CGPoint,
        frames: [PositionedLiquidSymbolKey],
        bounds: CGSize
    ) {
        let keyID = press.keyID
        guard let positioned = positioned(keyID: keyID, in: frames) else { return }
        let key = positioned.key
        let frame = positioned.frame
        let variants = insertVariants(for: key)
        pressedKeyIDs[press.id] = keyID
        guard variants.count > 1 else {
            if case .insert(let value) = key.action {
                presentSymbolPreview(text: value, source: positioned.visualFrame, bounds: bounds)
            }
            commitSymbolFromTap(key, emitsHaptic: false)
            return
        }
        // A held accent key must not block a second finger: every key inserts on
        // press, and only one popup is shown.
        guard activeVariantKeyID == nil else {
            nonPopupVariantTouchIDs.insert(press.id)
            HapticFeedback.playInputClick()
            commitSymbolFromTap(key, emitsHaptic: false)
            return
        }
        activeVariantKeyID = press.id
        HapticFeedback.playInputClick()
        variantTouchOrigin = point
        variantTouchCancelled = false
        if case .insert(let value) = key.action {
            presentSymbolPreview(text: value, source: positioned.visualFrame, bounds: bounds)
        }
        scheduleSymbolVariantPopup(variants, source: positioned.visualFrame, bounds: bounds)
    }

    private func handleGridMove(
        keyID press: KeyGridPress,
        point: CGPoint,
        frames: [PositionedLiquidSymbolKey]
    ) {
        let keyID = press.keyID
        guard activeVariantKeyID == press.id else { return }
        guard let positioned = positioned(keyID: keyID, in: frames),
              insertVariants(for: positioned.key).count > 1,
              var session = variantSession else { return }
        let absolute = point
        let index = KeyVariantPopup.selectedIndex(
            at: absolute, popupFrame: session.popupFrame, optionCount: session.options.count)
        guard session.selectedIndex != index else { return }
        session.selectedIndex = index
        variantSession = session
        HapticFeedback.variantHighlightChanged()
    }

    private func handleGridRelease(
        keyID press: KeyGridPress,
        cancelled: Bool,
        frames: [PositionedLiquidSymbolKey]
    ) {
        let keyID = press.keyID
        guard let positioned = positioned(keyID: keyID, in: frames) else { return }
        let key = positioned.key
        pressedKeyIDs.removeValue(forKey: press.id)
        if nonPopupVariantTouchIDs.remove(press.id) != nil {
            return
        }
        guard activeVariantKeyID == press.id else {
            if activeVariantKeyID == nil && !cancelled && insertVariants(for: key).count <= 1 {
                previewSession = nil
            }
            return
        }
        let sessionWasPresented = variantSession != nil
        let touchWasCancelled = cancelled || variantTouchCancelled
        activeVariantKeyID = nil
        variantHoldToken = nil
        variantTouchOrigin = nil
        variantTouchCancelled = false
        if touchWasCancelled {
            variantSession = nil
            previewSession = nil
        } else if sessionWasPresented {
            commitVariantSession()
        } else {
            // A quick tap on a key that *does* have variants. The base symbol was
            // not committed on press, because this path is only reached for keys
            // with variants — the plain-key branch above already committed those on
            // press. Gating this on "has no variants" made it unreachable, so every
            // plain tap on an accented symbol inserted nothing while the hold popup
            // worked.
            previewSession = nil
            if !cancelled {
                commitSymbolFromTap(key, emitsHaptic: false)
            }
        }
    }

    @ViewBuilder
    private func symbolKey(
        _ key: LiquidSymbolKey,
        keyID: String,
        frame: CGRect,
        visualFrame: CGRect,
        bounds: CGSize
    ) -> some View {
        if key.isSpacer {
            Color.clear
                .accessibilityHidden(true)
        } else if case .delete = key.action {
            let visual = surfaceLayout.commandKeyVisualSize
            KeyboardDeleteButton(
                onDelete: onDelete, onDeleteWord: onDeleteWord,
                visualWidth: visual.width,
                visualHeight: visual.height,
                hitWidth: frame.width, hitHeight: frame.height
            )
                .frame(width: frame.width, height: frame.height)
        } else {
            // The face only. Touches are owned by the shared UIKit key-grid owner,
            // the same component the letter page uses, so this surface no longer
            // installs a control per key. Per-key controls were destroyed and
            // recreated by SwiftUI on ordinary state changes, and a control missing
            // at release time silently dropped the character.
            ZStack {
                keyContent(key, frame: visualFrame)
                if pressedKeyIDs.values.contains(keyID) {
                    RoundedRectangle(
                        cornerRadius: key.isRoundCommand ? 18 : VoiceOnlyKeyboardPolicy.keyCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.primary.opacity(0.12))
                    .frame(
                        width: key.isRoundCommand ? surfaceLayout.commandKeyVisualSize.width : visualFrame.width,
                        height: key.isRoundCommand ? surfaceLayout.commandKeyVisualSize.height : visualFrame.height
                    )
                    .allowsHitTesting(false)
                }
            }
            .foregroundStyle(.primary)
            .frame(width: frame.width, height: frame.height)
            // Keep the full rectangular frame reachable, including edge keys.
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(key.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { commit(key) }
        }
    }

    private func insertVariants(for key: LiquidSymbolKey) -> [String] {
        guard case .insert(let value) = key.action else { return [] }
        return SymbolKeyVariants.options(for: value)
    }

    @ViewBuilder
    private func variantOverlay(_ session: KeyVariantSession, in _: CGSize) -> some View {
        KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: session.isEmoji
        )
        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
        .allowsHitTesting(false)
    }

    private func scheduleSymbolVariantPopup(_ variants: [String], source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.accentVariantsEnabled else { return }
        let token = UUID()
        variantHoldToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
            guard variantHoldToken == token,
                  variantSession == nil,
                  !variantTouchCancelled else { return }
            previewSession = nil
            variantSession = makeVariantSession(variants, source: source, in: bounds)
        }
    }

    private func presentSymbolPreview(text: String, source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, !text.isEmpty else { return }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius
        )
    }

    private func makeVariantSession(_ options: [String], source: CGRect, in bounds: CGSize) -> KeyVariantSession {
        HapticFeedback.variantPopupPresented()
        let popupFrame = KeyVariantPopup.frame(
            for: source,
            optionCount: options.count,
            isEmoji: false,
            in: bounds,
            topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
        )
        return KeyVariantSession(
            options: options,
            sourceFrame: source,
            popupFrame: popupFrame,
            isEmoji: false,
            selectedIndex: 0
        )
    }

    private func commitVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            previewSession = nil
            return
        }
        onInsert(session.options[session.selectedIndex])
        variantSession = nil
        previewSession = nil
    }

    private func commitSymbolFromTap(_ key: LiquidSymbolKey, emitsHaptic: Bool = true) {
        commit(key, emitsHaptic: emitsHaptic)
    }

    @ViewBuilder
    private func keyContent(_ key: LiquidSymbolKey, frame: CGRect) -> some View {
        switch key.action {
        case .togglePage:
            let visual = surfaceLayout.commandKeyVisualSize
            CommandKeyFace(
                text: key.label,
                plateWidth: visual.width,
                plateHeight: visual.height,
                textWeight: .medium
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .delete:
            let visual = surfaceLayout.commandKeyVisualSize
            CommandKeyFace(
                systemName: "delete.backward",
                plateWidth: visual.width,
                plateHeight: visual.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .insert:
            Text(key.label)
                .font(.system(size: 22, weight: .light))
                .frame(width: max(0, frame.width), height: max(0, frame.height))
                .letterKeyPlate()
        case .close:
            Text(key.label)
                .font(.system(size: 22, weight: .light))
                .frame(width: max(0, frame.width), height: max(0, frame.height))
        }
    }

    private func commit(_ key: LiquidSymbolKey, emitsHaptic: Bool = true) {
        guard !key.isSpacer else { return }
        if emitsHaptic {
            HapticFeedback.playInputClick()
        }
        switch key.action {
        case .insert(let value): onInsert(value)
        case .delete: onDelete()
        case .togglePage:
            switch VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(
                from: page == .symbols1 ? .symbols1 : .symbols2
            ) {
            case .symbols1ToSymbols2:
                onTogglePage(.symbols2)
            case .symbols2ToSymbols1:
                onTogglePage(.symbols1)
            }
        case .close: onClose()
        }
    }
}

private struct LiquidSymbolKey: Identifiable {
    enum Action {
        case insert(String)
        case delete
        case togglePage
        case close
    }

    let id: String
    let label: String
    let width: CGFloat
    let action: Action
    let isSpacer: Bool

    init(id: String, key: KeyboardSymbolsLayout.Key, page: KeyboardPage) {
        self.id = id
        self.width = CGFloat(key.width)
        switch key.kind {
        case .insert(let value):
            label = value
            action = .insert(value)
            isSpacer = false
        case .pageToggle:
            label = page == .symbols1 ? "#+=" : "123"
            action = .togglePage
            isSpacer = false
        case .delete:
            label = ""
            action = .delete
            isSpacer = false
        case .emoji, .voice, .space, .returnKey, .spacer:
            label = ""
            action = .close
            isSpacer = true
        }
    }

    var accessibilityLabel: String {
        switch action {
        case .insert: return label
        case .delete: return "Delete backward"
        case .togglePage: return label == "#+=" ? "More symbols" : "Return to numbers keyboard"
        case .close: return "Close"
        }
    }

    var isPageToggle: Bool {
        if case .togglePage = action { return true }
        return false
    }

    var isRoundCommand: Bool {
        switch action {
        case .togglePage, .delete:
            return true
        case .insert, .close:
            return false
        }
    }
}

private struct PositionedLiquidSymbolKey: Identifiable {
    let key: LiquidSymbolKey
    /// Continuous hit target (gaps absorbed).
    let frame: CGRect
    /// Original drawn plate/glyph rect.
    let visualFrame: CGRect
    var id: String { key.id }
}
