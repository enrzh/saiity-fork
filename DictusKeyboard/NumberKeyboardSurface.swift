import SwiftUI
import UIKit
import Foundation
import DictusCore

struct NumberKeyboardSurface: View {
    let style: HostFieldPolicy.NumberPadStyle
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let popupTopOverflow: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onKeyboard: () -> Void
    /// Where this surface sits inside the input view. The shared UIKit touch owner
    /// is mounted on the input view, so hit rectangles have to be published in
    /// that space rather than in the pad's own.
    let surfaceOrigin: CGPoint

    @State private var lettersHoldToken: UUID?
    @State private var lettersHoldOwnerID: String?
    @State private var openedLettersFromHold = false
    @State private var previewSession: KeyPreviewSession?
    /// Keys currently held, reported by the shared touch owner.
    @State private var pressedKeyIDs: [String: String] = [:]
    /// One handler instance for the surface's lifetime; see `refreshedGridHandlers`.
    @State private var gridHandlers = KeyGridHandlers()
    /// Memoises the derived grid; see `KeyGridCache`.
    @State private var gridCache = KeyGridCache<PositionedNumberPadKey>()

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                // Only the size and the host's number-pad style change this grid's
                // geometry, so a press highlight reuses it rather than rebuilding
                // every key.
                let cacheKey = "\(Int(proxy.size.width))x\(Int(proxy.size.height))"
                    + "-\(String(describing: style))"
                let frames = gridCache.resolve(key: cacheKey) {
                    let rows = positionedKeys(in: proxy.size)
                    return (rows, ownedGridGeometry(frames: rows, bounds: proxy.size))
                }
                let handlers = refreshedGridHandlers(frames: frames, bounds: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { item in
                        padKey(item.key, keyID: item.id, frame: item.visualFrame, hitFrame: item.frame, bounds: proxy.size)
                            .frame(width: item.frame.width, height: item.frame.height)
                            .position(x: item.frame.midX, y: item.frame.midY)
                    }
                    if previewSession != nil {
                        KeyPressPreviewHost(session: $previewSession)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                // The pad is owned by the same shared UIKit key-grid component the
                // letter and symbol pages use. Delete keeps its native repeat
                // control and is excluded, so those touches fall through to it.
                .keyGridInput(
                    geometry: gridCache.geometry,
                    handlers: handlers,
                    signature: cacheKey
                )
            }
        }
        .frame(width: availableWidth, height: availableHeight)
    }

    private var rows: [[KeyboardNumberPadLayout.Key]] {
        KeyboardNumberPadLayout.rows(
            for: style,
            decimalSeparator: Locale.current.decimalSeparator ?? "."
        )
    }

    private func positionedKeys(in size: CGSize) -> [PositionedNumberPadKey] {
        let edge = VoiceOnlyKeyboardPolicy.numberPadEdgeInset
        let content = CGSize(
            width: max(0, size.width - edge * 2),
            height: max(0, size.height - edge * 2)
        )
        let weights = rows.map { row in row.map { CGFloat($0.width) } }
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: weights,
            in: content,
            spacing: VoiceOnlyKeyboardPolicy.numberPadKeySpacing,
            inset: 0,
            rowSpacing: VoiceOnlyKeyboardPolicy.numberPadRowSpacing
        ).map { row in
            row.map { $0.offsetBy(dx: edge, dy: edge) }
        }
        let hitFrames = KeyboardKeyHitGeometry.frames(for: frames)
        // `zip` on the key row and the visual row does not guarantee the hit row is
        // as long, so indexing it by the same column could trap and kill the
        // extension. Zip all three together instead.
        return zip(rows, zip(frames, hitFrames)).enumerated().flatMap { rowIndex, pair in
            zip(pair.0, zip(pair.1.0, pair.1.1)).enumerated().map { columnIndex, item in
                PositionedNumberPadKey(
                    id: "\(style.rawValue)-\(rowIndex)-\(columnIndex)",
                    key: item.0,
                    frame: item.1.1,
                    visualFrame: item.1.0
                )
            }
        }
    }

    // MARK: - Shared UIKit touch owner

    /// A stable description of the grid, so the owner is refreshed on a real layout
    /// change rather than on every re-render.
    private func gridSignature(
        frames: [PositionedNumberPadKey],
        bounds: CGSize
    ) -> String {
        let rects = frames
            .map { "\($0.id):\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height))" }
            .joined(separator: "|")
        return "\(Int(bounds.width))x\(Int(bounds.height))#\(rects)"
    }

    /// Geometry for the shared owner, translated out of the pad's own space.
    private func ownedGridGeometry(
        frames: [PositionedNumberPadKey],
        bounds: CGSize
    ) -> KeyGridGeometry {
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
            currentRects.append(item.frame.offsetBy(dx: surfaceOrigin.x, dy: surfaceOrigin.y))
            currentPlates.append(item.visualFrame.offsetBy(dx: surfaceOrigin.x, dy: surfaceOrigin.y))
            currentIDs.append(item.id)
        }
        if !currentRects.isEmpty {
            rows.append(currentRects)
            keyIDs.append(currentIDs)
            plates.append(currentPlates)
        }
        return KeyGridGeometry(
            // Contiguous tiles spanning the whole grid: no dead band at the edges,
            // no overlap to arbitrate. Computed from the drawn plates, so the seams
            // still land in the gaps. Never used for layout.
            rows: KeyboardKeyHitGeometry.contiguousTiles(
                for: plates, in: CGRect(origin: surfaceOrigin, size: bounds)),
            keyIDs: keyIDs,
            gridRect: CGRect(origin: surfaceOrigin, size: bounds),
            // Delete keeps its native repeat control; spacers own nothing.
            excludedRects: frames.compactMap { item in
                guard case .delete = item.key.kind else { return nil }
                return item.frame.offsetBy(dx: surfaceOrigin.x, dy: surfaceOrigin.y)
            }
        )
    }

    /// Refreshes the surface's single handler instance in place and returns it.
    ///
    /// Stable identity, current closures: the bus tracks ownership by this object's
    /// identity, while activation is gated on geometry changing.
    private func refreshedGridHandlers(
        frames: [PositionedNumberPadKey],
        bounds: CGSize
    ) -> KeyGridHandlers {
        gridHandlers.refresh(
            onPress: { keyID, _ in
                handleGridPress(keyID: keyID, frames: frames, bounds: bounds)
            },
            onMove: { _, _ in },
            onRelease: { keyID, cancelled in
                handleGridRelease(keyID: keyID, cancelled: cancelled, frames: frames)
            }
        )
        return gridHandlers
    }

    private func positioned(
        keyID: String,
        in frames: [PositionedNumberPadKey]
    ) -> PositionedNumberPadKey? {
        frames.first { $0.id == keyID }
    }

    private func handleGridPress(
        keyID press: KeyGridPress,
        frames: [PositionedNumberPadKey],
        bounds: CGSize
    ) {
        let keyID = press.keyID
        guard let item = positioned(keyID: keyID, in: frames) else { return }
        switch item.key.kind {
        case .spacer, .delete:
            return
        case .letters:
            pressedKeyIDs[press.id] = keyID
            HapticFeedback.playInputClick()
            onKeyboard()
        case .insert(let value, let holdLetters):
            pressedKeyIDs[press.id] = keyID
            HapticFeedback.playInputClick()
            guard holdLetters else {
                onInsert(value)
                return
            }
            guard lettersHoldOwnerID == nil else {
                onInsert(value)
                return
            }
            lettersHoldOwnerID = press.id
            openedLettersFromHold = false
            presentPadPreview(text: value, source: item.visualFrame, bounds: bounds)
            let token = UUID()
            lettersHoldToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
                guard lettersHoldToken == token else { return }
                openedLettersFromHold = true
                previewSession = nil
                onKeyboard()
            }
        }
    }

    private func handleGridRelease(
        keyID press: KeyGridPress,
        cancelled: Bool,
        frames: [PositionedNumberPadKey]
    ) {
        let keyID = press.keyID
        guard let item = positioned(keyID: keyID, in: frames) else { return }
        pressedKeyIDs.removeValue(forKey: press.id)
        guard lettersHoldOwnerID == press.id else { return }
        lettersHoldOwnerID = nil
        lettersHoldToken = nil
        previewSession = nil
        guard !cancelled, !openedLettersFromHold else { return }
        if case .insert(let value, let holdLetters) = item.key.kind, holdLetters {
            onInsert(value)
        }
    }

    @ViewBuilder
    private func padKey(
        _ key: KeyboardNumberPadLayout.Key,
        keyID: String,
        frame: CGRect,
        hitFrame: CGRect,
        bounds: CGSize
    ) -> some View {
        switch key.kind {
        case .spacer:
            Color.clear.accessibilityHidden(true)
        case .letters:
            ZStack {
                CommandKeyFace(
                    text: "ABC",
                    plateWidth: frame.width,
                    plateHeight: frame.height,
                    cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                    textPointSize: 16
                )
                padPressHighlight(keyID: keyID, key: key, frame: frame)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open letter keyboard")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onKeyboard() }
        case .delete:
            KeyboardDeleteButton(
                onDelete: onDelete,
                onDeleteWord: onDeleteWord,
                visualWidth: frame.width,
                visualHeight: frame.height,
                visualCornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                hitWidth: hitFrame.width,
                hitHeight: hitFrame.height
            )
        case .insert(let value, let holdLetters):
            ZStack {
                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 22, weight: .light))
                    if holdLetters {
                        Text("ABC")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .letterKeyPlate(cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius)
                // The face only. Touches are owned by the shared UIKit key-grid
                // component, the same one the letter and symbol pages use, so the
                // pad no longer installs a control per key.
                padPressHighlight(keyID: keyID, key: key, frame: frame)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value)
            .accessibilityHint(holdLetters ? "Hold to open the letter keyboard." : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onInsert(value) }
        }
    }

    /// Press feedback drawn by the surface, driven by the state the shared touch
    /// owner reports. A key cannot lose its highlight by being rebuilt, because
    /// the press is tracked by the owner rather than by a control per key.
    @ViewBuilder
    private func padPressHighlight(
        keyID: String,
        key: KeyboardNumberPadLayout.Key,
        frame: CGRect
    ) -> some View {
        if pressedKeyIDs.values.contains(keyID) {
            RoundedRectangle(
                cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.12))
            .frame(width: frame.width, height: frame.height)
            .allowsHitTesting(false)
        }
    }

    private func presentPadPreview(text: String, source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, !text.isEmpty else { return }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: popupTopOverflow
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius
        )
    }
}

private struct PositionedNumberPadKey: Identifiable {
    let id: String
    let key: KeyboardNumberPadLayout.Key
    let frame: CGRect
    let visualFrame: CGRect
}
