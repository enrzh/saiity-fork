import SwiftUI
import UIKit
import Foundation
import DictusCore

struct LetterKeyboardSurface: View {
    let surfaceLayout: VoiceOnlyKeyboardPolicy.Layout
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onBackToVoice: () -> Void
    let onSymbols: () -> Void
    let onEmoji: () -> Void
    let showsSymbolsControl: Bool
    var fieldKeys: HostFieldPolicy.LetterFieldKeys = .standard
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void

    @State private var page: KeyboardPage = .normal
    @State private var variantSession: KeyVariantSession?
    @State private var previewSession: KeyPreviewSession?
    @State private var variantHoldToken: UUID?
    @State private var variantTouchOrigin: CGPoint?
    @State private var variantTouchCancelled = false
    @State private var activeVariantKeyID: String?
    @State private var nonPopupVariantTouchIDs: Set<String> = []
    /// Keys currently held down, reported by the single capture view. Press
    /// feedback is now driven by the touch owner rather than by each key's own
    /// control, so a key cannot lose its highlight by being rebuilt.
    @State private var pressedKeyIDs: [String: String] = [:]
    /// One handler instance for the surface's lifetime. The bus tracks ownership by
    /// this object's identity, so it must not be replaced per render.
    @State private var gridHandlers = KeyGridHandlers()
    /// Memoises the derived grid. See `KeyGridCache` — rebuilding this on every
    /// render is what made fast typing lag.
    @State private var gridCache = KeyGridCache<PositionedLetterKey>()
    @ObservedObject private var suggestionState = SuggestionState.shared
    // WHY key ids are row/column and nothing else: they used to be prefixed
    // with a per-instance `UUID()` held in @State. Every time SwiftUI rebuilt
    // this surface — which the keyboard does on each mode apply and state
    // refresh — that UUID changed, so every key's `ForEach` identity changed
    // with it and SwiftUI destroyed and recreated all the per-key touch
    // controls. A finger resting on a key at that instant lost its control
    // mid-touch: UIKit then delivered neither `touchesEnded` nor
    // `touchesCancelled`, the release callback never ran, and the letter never
    // committed. Measured on device: 13 touches began, 4 ended, 0 cancelled.
    // That was the "typing is almost not responsive" report.
    // A stable identity lets SwiftUI reuse the same control, so the release
    // always lands on the control that saw the press.
    @AppStorage(SharedKeys.language, store: AppGroup.defaults) private var languageCode = SupportedLanguage.active.rawValue

    private var shiftSymbolName: String {
        page == .capslock ? "capslock.fill" : page == .shifted ? "shift.fill" : "capslock"
    }

    private let bottomBarHeight: CGFloat = 44
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)

    /// The key grid's size, derived rather than measured.
    ///
    /// This deliberately avoids `GeometryReader`. A `GeometryReader` has no
    /// intrinsic size and does not propagate hit-testing reliably to a
    /// `UIViewRepresentable` inside it, which left the grid's touch owner
    /// unreachable while the keys rendered perfectly — a keyboard that looked
    /// correct and ignored every tap. The emoji page has the identical structure
    /// and works precisely because it sizes its canvas from the layout it is given
    /// and lays it out in a plain `VStack`, with no `GeometryReader` anywhere near
    /// the touch-owning view.
    private var gridSize: CGSize {
        CGSize(
            width: availableWidth,
            height: max(0, availableHeight - commandRowGap - bottomBarHeight - chromeBottomInset)
        )
    }

    var body: some View {
        let _ = (onBackToVoice, showsSymbolsControl)
        let gridSize = gridSize
        VStack(spacing: 0) {
            // The keys themselves are drawn and hit-tested by one UIKit view, mounted
            // on the input view by the controller. SwiftUI contributes nothing but
            // the space it occupies, so the plate that is drawn and the target that
            // is pressed are the same rectangle by construction.
            //
            // The old arrangement drew the faces here and resolved touches in a
            // separate view from geometry published through a global bus. Two
            // systems describing the same keys is what let a visible key have no
            // target, and a target have no visible key.
            Color.clear
                .frame(width: gridSize.width, height: gridSize.height)
                .allowsHitTesting(false)
            Color.clear.frame(height: commandRowGap)
            AuxiliaryBottomBar(
                layout: surfaceLayout,
                numbersTitle: "123",
                onNumbers: onSymbols,
                onLetters: {},
                onEmoji: onEmoji,
                spaceFrame: surfaceLayout.letterSpaceFrame,
                returnFrame: surfaceLayout.chromeReturnFrame,
                periodFrame: surfaceLayout.letterPeriodFrame,
                onPeriod: onInsert,
                onDelete: onDelete,
                onSpace: onSpace,
                onSpaceCursorBegan: onSpaceCursorBegan,
                onSpaceCursorMoved: onSpaceCursorMoved,
                onSpaceCursorEnded: onSpaceCursorEnded,
                onReturn: onReturn,
                showsLettersControl: false,
                showsPeriodKey: true,
                fieldKeys: fieldKeys,
                onSymbolInsert: onInsert
            )
            .frame(width: availableWidth, height: bottomBarHeight)
            Color.clear.frame(height: chromeBottomInset)
        }
        .frame(width: availableWidth, height: availableHeight)
        .onChange(of: LayoutType.active) { _, _ in
            resetLetterPageTransientState()
        }
        .onChange(of: languageCode) { _, _ in
            resetLetterPageTransientState()
        }
        .onChange(of: page) { _, _ in
            suggestionState.clearAdaptiveTouchPrediction()
        }
        .onDisappear {
            suggestionState.clearAdaptiveTouchPrediction()
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
    }

    private func resetLetterPageTransientState() {
        page = .normal
        suggestionState.clearAdaptiveTouchPrediction()
        variantSession = nil
        previewSession = nil
        variantHoldToken = nil
        variantTouchOrigin = nil
        variantTouchCancelled = false
        KeyboardState.shared.lastShiftTapDate = .distantPast
        activeVariantKeyID = nil
        nonPopupVariantTouchIDs.removeAll()
    }

    /// The keys themselves live in `KeyGridView`, which the controller mounts on the
    /// input view and owns end to end. This surface contributes only the space they
    /// occupy plus the bar and suggestion lane, so there is nothing left to sync
    /// here — and a second copy of the row definitions would be a second source of
    /// truth that could disagree with what is on screen.

    private var rows: [[KeyDefinition]] {
        let _ = languageCode
        guard let layout = KeyboardLayouts.current().currentDeviceLayout else { return [] }
        let pageRows: [[KeyDefinition]]
        switch page {
        case .normal:
            pageRows = layout.normal
        case .shifted, .capslock:
            pageRows = layout.shifted
        case .symbols1, .symbols2:
            pageRows = layout.normal
        }
        // The common bottom bar owns emoji, symbols, space and return. Keeping
        // those definitions out of this grid prevents a second shifting row.
        return Array(pageRows.dropLast())
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLetterKey] {
        let geometry = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(size.width))
        let edgeInset = geometry.keyGridInset
        let rowSpacing = geometry.keyRowSpacing
        let keySpacing = geometry.keySpacing
        let currentRows = rows
        let weights = currentRows.map { row in row.map { CGFloat($0.size.width) } }
        let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
            in: size.height,
            rowSpacing: rowSpacing
        )
        var frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
            for: weights,
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
                rowFrame: CGRect(x: edgeInset, y: first.minY,
                                 width: max(0, size.width - edgeInset * 2),
                                 height: lastRowHeight),
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
        if let lastRow = frames.indices.last,
           currentRows.indices.contains(lastRow),
           lastRow < currentRows.count {
            frames[lastRow] = frames[lastRow].map {
                CGRect(x: $0.minX, y: deleteFrame.minY, width: $0.width, height: deleteFrame.height)
            }
            for (index, key) in currentRows[lastRow].enumerated() {
                if case .backspace = key.type, frames[lastRow].indices.contains(index) {
                    frames[lastRow][index] = deleteFrame
                }
            }
        }
        let hitLabels = currentRows.map { row in
            row.map { key -> String? in
                guard case .input(let value, _) = key.type,
                      value.count == 1,
                      value != KeyboardLayouts.emojiKeyGlyph else { return nil }
                return value
            }
        }
        let prediction = KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
            ? suggestionState.adaptiveTouchPrediction : nil
        var hitFrames = KeyboardKeyHitGeometry.frames(
            for: frames,
            labels: hitLabels,
            probabilities: prediction,
            maximumPredictionShift: 4
        )
        // Delete must not move or resize between pages. The emoji page uses
        // `boardDeleteFrame` directly for both its visual and its hit rect,
        // while this page used to push the backspace through the prediction
        // seamer, which could widen its hit rect into the neighbouring key's
        // gap. Pin it to the same shared frame so the control is identical on
        // every surface.
        if let lastRow = hitFrames.indices.last,
           currentRows.indices.contains(lastRow),
           lastRow < currentRows.count {
            for (index, key) in currentRows[lastRow].enumerated() {
                if case .backspace = key.type, hitFrames[lastRow].indices.contains(index) {
                    hitFrames[lastRow][index] = deleteFrame
                }
            }
        }
        // Row counts are not guaranteed to agree: the solver can return fewer rows
        // than `currentRows` has when the available height is degenerate — and this
        // used to trap outright, killing the extension on launch, because every row
        // index below came from `currentRows` and was applied to the solved arrays
        // unchecked. A keyboard must never crash because its container is briefly
        // the wrong size.
        let rowCount = min(currentRows.count, min(frames.count, hitFrames.count))
        guard rowCount > 0 else { return [] }
        return (0..<rowCount).flatMap { rowIndex -> [PositionedLetterKey] in
            let row = currentRows[rowIndex]
            let rowHits = hitFrames[rowIndex]
            let rowPlates = frames[rowIndex]
            // A solved row can still be shorter than its key row; zipping the
            // columns keeps the two in step instead of reading past the end.
            return zip(row.indices, zip(rowHits, rowPlates)).map { columnIndex, pair in
                PositionedLetterKey(
                    id: "letter-\(rowIndex)-\(columnIndex)",
                    key: row[columnIndex],
                    frame: pair.0,
                    visualFrame: pair.1,
                    row: rowIndex,
                    column: columnIndex
                )
            }
        }
    }

    /// Groups the flat key list into rows for the capture view.
    ///
    /// Rectangles and identities are appended together from one sorted pass, so
    /// they cannot drift out of parallel — a mismatch here would resolve a
    /// position to the wrong key's identity and commit the wrong character.
    private func captureGeometry(
        _ frames: [PositionedLetterKey]
    ) -> (rows: [[CGRect]], keyIDs: [[String]]) {
        let rowCount = (frames.map(\.row).max() ?? -1) + 1
        guard rowCount > 0 else { return ([], []) }
        var rows = Array(repeating: [CGRect](), count: rowCount)
        var keyIDs = Array(repeating: [String](), count: rowCount)
        let ordered = frames.sorted {
            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
        }
        for frame in ordered where frame.row < rowCount {
            rows[frame.row].append(frame.frame)
            keyIDs[frame.row].append(frame.id)
        }
        return (rows, keyIDs)
    }

    /// Builds the callbacks the UIKit owner invokes, bound to the geometry that
    /// was just laid out.
    ///
    /// This is a function rather than inline statements because a `ViewBuilder`
    /// only accepts expressions, and the owner has to be refreshed with closures
    /// that close over the current frames rather than stale ones.
    /// Refreshes the surface's single handler instance in place and returns it.
    ///
    /// The instance must stay stable because the bus tracks grid ownership by its
    /// identity, but its closures must never keep pointing at an earlier render.
    /// Activation is gated on geometry changing, so a grid that redrew for any other
    /// reason — a press highlight, an accent popup, the shift page — would
    /// otherwise keep dispatching through stale callbacks. That is precisely the
    /// shape of the bug where slow typing worked and fast typing dropped presses.
    ///
    /// A function rather than inline assignment because a `ViewBuilder` only
    /// accepts view expressions.
    private func refreshedGridHandlers(
        frames: [PositionedLetterKey],
        bounds: CGSize
    ) -> KeyGridHandlers {
        gridHandlers.refresh(
            onPress: { keyID, point in
                handleCapturedPress(keyID: keyID, point: point, frames: frames, bounds: bounds)
            },
            onMove: { keyID, point in
                handleCapturedMove(keyID: keyID, point: point, frames: frames)
            },
            onRelease: { keyID, cancelled in
                handleCapturedRelease(keyID: keyID, cancelled: cancelled, frames: frames)
            }
        )
        return gridHandlers
    }

    /// A stable description of the grid, so the owner is refreshed when geometry
    /// actually changes rather than on every re-render.
    private func captureGeometrySignature(
        _ frames: [PositionedLetterKey],
        gridSize: CGSize
    ) -> String {
        let rects = frames
            .sorted { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row }
            .map { "\($0.id):\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height))" }
            .joined(separator: "|")
        return "\(Int(gridSize.width))x\(Int(gridSize.height))#\(rects)"
    }

    /// The geometry handed to the UIKit owner.
    ///
    /// The owner is mounted on the input view, whose origin is the top-left of the
    /// whole keyboard. This surface is not: `KeyboardRootView` places it at
    /// `layout.surfaceFrame`, which sits below the suggestion lane and carries a
    /// horizontal inset. Publishing surface-local rectangles at origin `.zero`
    /// therefore offset every key by the lane height, so a touch on a visible key
    /// resolved to the wrong row — or to nothing.
    ///
    /// Every rectangle is translated into the owner's space by the surface's own
    /// origin, and the grid rectangle claims that translated area so the owner
    /// cannot reach the suggestion lane or the board chrome.
    ///
    /// The rows published here are **contiguous tiles spanning the whole grid**,
    /// the shape a real keyboard uses: edge to edge, no dead band, no overlap, and
    /// therefore nothing to arbitrate. They are computed from the drawn plates, so
    /// the seams still land in the gaps between keys, and the outer edges are the
    /// grid's own edges so the margin beside the first and last key is live.
    ///
    /// None of this is layout. `ForEach` still positions every key by
    /// `frame`/`visualFrame` from `positionedKeys`, so no plate, container or
    /// layout box can move or resize because of the tiles. That separation is why
    /// this is built here and not in `positionedKeys`' return value.
    private func ownedGridGeometry(
        frames: [PositionedLetterKey],
        bounds: CGSize
    ) -> KeyGridGeometry {
        let capture = captureGeometry(frames)
        let origin = surfaceLayout.surfaceFrame.origin
        let gridRect = CGRect(origin: origin, size: bounds)
        let visualRows = orderedByPosition(frames).map { row in
            row.map { $0.visualFrame.offsetBy(dx: origin.x, dy: origin.y) }
        }
        let tiles = KeyboardKeyHitGeometry.contiguousTiles(
            for: visualRows,
            in: gridRect,
            labels: hitLabels,
            probabilities: prediction
        )
        return KeyGridGeometry(
            rows: tiles,
            keyIDs: capture.keyIDs,
            gridRect: gridRect,
            // Delete and shift keep their own controls, which carry repeat and
            // page behaviour this owner does not model. They are excluded here so
            // the owner hands those touches straight back to UIKit.
            excludedRects: frames
                .filter { isDedicatedControl($0.key) }
                .map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) }
        )
    }

    /// Single-character labels per row, in the same row/column order as
    /// `captureGeometry`. Only real letters take part in hit prediction.
    private var hitLabels: [[String?]] {
        rows.map { row in
            row.map { key -> String? in
                guard case .input(let value, _) = key.type,
                      value.count == 1,
                      value != KeyboardLayouts.emojiKeyGlyph else { return nil }
                return value
            }
        }
    }

    /// The prediction the tiles may be biased by, or nil when the user has turned
    /// adaptive hit prediction off.
    private var prediction: NextCharacterProbabilities? {
        KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
            ? suggestionState.adaptiveTouchPrediction
            : nil
    }

    /// Frames grouped into rows in visual order, matching the row/column order
    /// `captureGeometry` assigns identities in.
    private func orderedByPosition(_ frames: [PositionedLetterKey]) -> [[PositionedLetterKey]] {
        let rowCount = (frames.map(\.row).max() ?? -1) + 1
        guard rowCount > 0 else { return [] }
        var rows = Array(repeating: [PositionedLetterKey](), count: rowCount)
        for frame in frames.sorted(by: keyOrder) where frame.row < rowCount {
            rows[frame.row].append(frame)
        }
        return rows
    }

    private func keyOrder(_ lhs: PositionedLetterKey, _ rhs: PositionedLetterKey) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }

    /// Keys that keep a dedicated control rather than being handled by the single
    /// touch owner.
    private func isDedicatedControl(_ key: KeyDefinition) -> Bool {
        switch key.type {
        case .shift, .backspace, .spacer:
            return true
        default:
            return false
        }
    }

    private func positioned(
        keyID: String,
        in frames: [PositionedLetterKey]
    ) -> PositionedLetterKey? {
        frames.first { $0.id == keyID }
    }

    private func handleCapturedPress(
        keyID press: KeyGridPress,
        point: CGPoint,
        frames: [PositionedLetterKey],
        bounds: CGSize
    ) {
        let keyID = press.keyID
        guard let positioned = positioned(keyID: keyID, in: frames),
              !isDedicatedControl(positioned.key) else { return }
        let key = positioned.key
        pressedKeyIDs[press.id] = keyID
        if alternateVariants(for: key).count > 1 {
            // Accent keys still decide on release: a held key has to be able to
            // commit the popup option instead of the base character.
            handleLetterVariantBegan(
                key: key, keyID: press.id, point: point,
                frame: positioned.frame, bounds: bounds)
        } else {
            handleLetterKeyBegan(
                key: key, keyID: press.id,
                frame: positioned.visualFrame, bounds: bounds)
            // Insert on touch-down, the way every other keyboard does.
            //
            // This used to wait for the lift. On a device that reads as "the key
            // did not respond" for the whole duration of the tap, and a quick tap
            // looks like nothing happened at all until the finger is up. The
            // reason it had to wait is gone: the grid has one stable UIKit touch
            // owner, so a render caused by the insertion cannot destroy the view
            // that is holding the touch, and the geometry is memoized, so the
            // re-render does not rebuild the key rectangles.
            commit(key)
        }
    }

    private func handleCapturedMove(
        keyID press: KeyGridPress,
        point: CGPoint,
        frames: [PositionedLetterKey]
    ) {
        let keyID = press.keyID
        guard let positioned = positioned(keyID: keyID, in: frames),
              alternateVariants(for: positioned.key).count > 1 else { return }
        handleLetterVariantMoved(
            keyID: press.id, point: point, frame: positioned.frame)
    }

    private func handleCapturedRelease(
        keyID press: KeyGridPress,
        cancelled: Bool,
        frames: [PositionedLetterKey]
    ) {
        let keyID = press.keyID
        guard let positioned = positioned(keyID: keyID, in: frames),
              !isDedicatedControl(positioned.key) else { return }
        let key = positioned.key
        pressedKeyIDs.removeValue(forKey: press.id)
        if alternateVariants(for: key).count > 1 {
            handleLetterVariantEnded(key: key, keyID: press.id, cancelled: cancelled)
        } else {
            // The character was inserted on touch-down. The lift only ends the
            // highlight and the preview, exactly like releasing a system key.
            dismissKeyPreview(ownerKeyID: press.id)
        }
    }

    @ViewBuilder
    private func letterKey(
        _ key: KeyDefinition,
        keyID: String,
        frame: CGRect,
        visualFrame: CGRect,
        bounds: CGSize
    ) -> some View {
        let variants = alternateVariants(for: key)
        Group {
            switch key.type {
            case .spacer:
                Color.clear.accessibilityHidden(true)
            case .shift:
                ZStack {
                    letterKeyLabel(for: key, frame: visualFrame)
                    ImmediateKeyButton(
                        onTouchDown: {
                            handleShiftTap()
                        },
                        onTouchUp: {},
                        highlightCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                        highlightSize: surfaceLayout.commandKeyVisualSize
                    )
                }
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("shift-key")
                    .accessibilityLabel(shiftAccessibilityLabel)
                    .accessibilityValue(shiftAccessibilityValue)
                    .accessibilityAddTraits(page == .normal ? .isButton : [.isButton, .isSelected])
            case .backspace:
                let visual = surfaceLayout.commandKeyVisualSize
                KeyboardDeleteButton(
                    onDelete: onDelete,
                    onDeleteWord: onDeleteWord,
                    visualWidth: visual.width,
                    visualHeight: visual.height,
                    visualCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                    hitWidth: frame.width,
                    hitHeight: frame.height
                )
                .frame(width: frame.width, height: frame.height)
            default:
                // A Button and a high-priority long-press both receive the same
                // touch-up on some keyboard hosts. That race inserts the base
                // letter and the selected accent. Variant keys therefore have
                // exactly one gesture owner, and it is now the single capture
                // view for the whole grid rather than a control per key: a short
                // release inserts the base key, a long release commits one popup
                // option. The decision is made in `handleCapturedPress` from the
                // key's own identity, not from which view received the touch.
                ZStack {
                    letterKeyLabel(for: key, frame: visualFrame)
                    if pressedKeyIDs.values.contains(keyID) {
                        RoundedRectangle(cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius,
                                         style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: visualFrame.width, height: visualFrame.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    key.type == .backspace
                        ? "Delete backward"
                        : key.accessibilityLabel(for: page) ?? "Keyboard key"
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { commit(key) }
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    private func letterKeyLabel(for key: KeyDefinition, frame: CGRect) -> some View {
        Group {
            if case .shift = key.type {
                let visual = surfaceLayout.commandKeyVisualSize
                CommandKeyFace(
                    systemName: shiftSymbolName,
                    plateWidth: visual.width,
                    plateHeight: visual.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                letterGlyph(for: key)
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .letterKeyPlate()
            }
        }
    }

    @ViewBuilder
    private func letterGlyph(for key: KeyDefinition) -> some View {
        switch key.type {
        case .input(let value, _):
            Text(value)
                .font(.system(size: 22, weight: .regular))
        case .shift:
            Image(systemName: shiftSymbolName)
                .font(.system(size: 16, weight: .semibold))
        case .symbols:
            Text("123")
                .font(.system(size: 14, weight: .medium))
        case .returnkey(let name):
            Text(name)
                .font(.system(size: 14, weight: .medium))
        case .backspace:
            Image(systemName: "delete.backward")
                .font(.system(size: 16, weight: .semibold))
        default:
            EmptyView()
        }
    }

    private func commit(_ key: KeyDefinition) {
        switch key.type {
        case .input(let value, _):
            if value == KeyboardLayouts.emojiKeyGlyph {
                onEmoji()
            } else {
                onInsert(value)
                if page == .shifted { page = .normal }
            }
        case .shift:
            page = page == .capslock ? .normal : (page == .shifted ? .normal : .shifted)
        case .symbols:
            onSymbols()
        case .returnkey:
            onReturn()
        case .spacebar:
            onSpace()
        default:
            break
        }
    }

    private func commitTap(_ key: KeyDefinition) {
        HapticFeedback.playInputClick()
        if case .backspace = key.type {
            onDelete()
        } else {
            commit(key)
        }
    }

    private var shiftAccessibilityLabel: String {
        switch page {
        case .capslock: return "Caps Lock"
        case .shifted: return "Shift"
        default: return "Shift"
        }
    }

    private var shiftAccessibilityValue: String {
        switch page {
        case .capslock: return "Caps Lock on"
        case .shifted: return "Next letter uppercase"
        default: return "Off"
        }
    }

    private func handleShiftTap() {
        let now = Date()
        let isSecondTap = now.timeIntervalSince(KeyboardState.shared.lastShiftTapDate) <= KeyboardShiftState.doubleTapWindow
        let currentState: KeyboardShiftState
        switch page {
        case .capslock: currentState = .capsLock
        case .shifted: currentState = .shifted
        default: currentState = .normal
        }
        let nextState = currentState.state(afterTapIsWithinDoubleTapWindow: isSecondTap)
        switch nextState {
        case .normal: page = .normal
        case .shifted: page = .shifted
        case .capsLock: page = .capslock
        }
        KeyboardState.shared.lastShiftTapDate = nextState == .shifted ? now : .distantPast
        HapticFeedback.playInputClick()
    }

    private func alternateVariants(for key: KeyDefinition) -> [String] {
        guard case .input(let value, _) = key.type,
              value.count == 1,
              let accents = AccentedCharacters.accents(for: value),
              !accents.isEmpty else {
            return []
        }

        let transformedAccents = (page == .shifted || page == .capslock)
            ? accents.map(KeyCaseTransform.uppercased)
            : accents
        return [value] + transformedAccents
    }

    private func handleLetterKeyBegan(key: KeyDefinition, keyID: String, frame: CGRect, bounds: CGSize) {
        // Press feedback only. The insertion happens in `handleCapturedPress`,
        // before this returns, so the field and the key react together.
        HapticFeedback.playInputClick()
        presentKeyPreview(text: previewText(for: key), source: frame, bounds: bounds, ownerKeyID: keyID)
    }

    private func handleLetterVariantBegan(
        key: KeyDefinition,
        keyID: String,
        point: CGPoint,
        frame: CGRect,
        bounds: CGSize
    ) {
        let variants = alternateVariants(for: key)
        guard !variants.isEmpty else {
            handleLetterKeyBegan(key: key, keyID: keyID, frame: frame, bounds: bounds)
            return
        }
        // A held accent key must not block a second finger from typing another
        // accent/base key. Only one popup is shown, while concurrent touches
        // commit their base key independently on release.
        guard activeVariantKeyID == nil else {
            nonPopupVariantTouchIDs.insert(keyID)
            HapticFeedback.playInputClick()
            presentKeyPreview(text: previewText(for: key), source: frame, bounds: bounds, ownerKeyID: keyID)
            return
        }
        activeVariantKeyID = keyID
        variantSession = nil
        presentKeyPreview(text: previewText(for: key), source: frame, bounds: bounds, ownerKeyID: keyID)
        variantTouchOrigin = point
        variantTouchCancelled = false
        HapticFeedback.playInputClick()
        scheduleLetterVariantPopup(variants, source: frame, bounds: bounds)
    }

    private func handleLetterVariantMoved(keyID: String, point: CGPoint, frame: CGRect) {
        guard activeVariantKeyID == keyID else { return }
        moveLetterVariant(to: point)
    }

    private func handleLetterVariantEnded(key: KeyDefinition, keyID: String, cancelled: Bool) {
        if nonPopupVariantTouchIDs.remove(keyID) != nil {
            if !cancelled { commit(key) }
            dismissKeyPreview(ownerKeyID: keyID)
            return
        }
        guard activeVariantKeyID == keyID else {
            if !cancelled { commit(key) }
            return
        }
        activeVariantKeyID = nil
        variantHoldToken = nil
        variantTouchOrigin = nil
        defer {
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
        }
        guard !cancelled, !variantTouchCancelled else { return }
        if variantSession != nil { commitLetterVariantSession() }
        else { commit(key) }
    }

    private func moveLetterVariant(to point: CGPoint) {
        if var session = variantSession {
            let index = KeyVariantPopup.selectedIndex(at: point, popupFrame: session.popupFrame,
                                                     optionCount: session.options.count)
            if session.selectedIndex != index {
                session.selectedIndex = index
                variantSession = session
                HapticFeedback.variantHighlightChanged()
            }
        }
    }

    private func scheduleLetterVariantPopup(_ variants: [String], source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.accentVariantsEnabled else { return }
        let token = UUID()
        variantHoldToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
            guard variantHoldToken == token,
                  variantSession == nil,
                  !variantTouchCancelled else { return }
            previewSession = nil
            variantSession = makeLetterVariantSession(variants, source: source, in: bounds)
        }
    }

    private func previewText(for key: KeyDefinition) -> String? {
        guard case .input(let value, _) = key.type,
              value != KeyboardLayouts.emojiKeyGlyph else { return nil }
        return value
    }

    /// One popup, first press owns it.
    ///
    /// Two-finger typing put two keys through this in quick succession and the
    /// second simply overwrote the first, so the balloon showed the wrong
    /// letter; then whichever finger lifted first dismissed a preview it did not
    /// own. Measured on device: 24 of 40 committed keys did not own the popup
    /// they were typing. The popup now belongs to the first press until it
    /// lifts, and a non-owning release leaves it alone.
    private func presentKeyPreview(text: String?, source: CGRect, bounds: CGSize, ownerKeyID: String) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, let text, !text.isEmpty else { return }
        if let existing = previewSession, existing.ownerKeyID != ownerKeyID {
            return
        }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius,
            ownerKeyID: ownerKeyID
        )
    }

    private func dismissKeyPreview(ownerKeyID: String? = nil) {
        // A release only clears the popup it owns, so a second finger lifting
        // cannot wipe the first finger's preview.
        if let ownerKeyID, let owner = previewSession?.ownerKeyID, owner != ownerKeyID {
            return
        }
        previewSession = nil
    }

    private func makeLetterVariantSession(_ options: [String], source: CGRect, in bounds: CGSize) -> KeyVariantSession {
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

    private func commitLetterVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            previewSession = nil
            return
        }
        onInsert(session.options[session.selectedIndex])
        if page == .shifted {
            page = .normal
        }
        variantSession = nil
        previewSession = nil
    }
}

private struct PositionedLetterKey: Identifiable {
    let id: String
    let key: KeyDefinition
    /// Continuous hit target (gaps absorbed).
    let frame: CGRect
    /// Original drawn plate/glyph rect (inset inside `frame`).
    let visualFrame: CGRect
    let row: Int
    let column: Int
}
