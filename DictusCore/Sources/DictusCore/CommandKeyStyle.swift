// DictusCore/Sources/DictusCore/CommandKeyStyle.swift
//
// The default styling for a command button: shift, delete, the 123 and #+= page
// toggles, the emoji key, return, and everything in the bottom bar.
//
// This exists because "a command button" had two implementations that drifted apart.
// The emoji page's delete is SwiftUI: `CommandKeyFace` scales it to 0.94 and fades it
// to 0.72. The grid's delete is Core Graphics, in a view that draws and hit-tests
// every key, and it drew a flat 18% label wash instead. Both sit on the same glass
// pill with the same corner radius, so the only visible difference between them was
// that one of them depressed and the other only tinted.
//
// One set of numbers, read by both renderers, is what makes them the same button.
//
// It lives here rather than on `VoiceOnlyKeyboardPolicy` because `VoiceOnlyKeyboardPolicy`
// is the keyboard's layout authority, and a layout type is the worst place to hang a
// press treatment that three renderers have to agree on.
//
// It used to say that instead: that the keyboard target declared its own copy of
// `VoiceOnlyKeyboardPolicy`, which shadowed this framework's. That copy was real, and
// it was a live trap — it was never in the Xcode target, so it never compiled, but a
// single "Add Files" in Xcode would have made it win over the framework's and broken
// the build in six independent ways. The duplicate directory is deleted, and that
// shadow is no longer possible. The separation is worth keeping anyway.

import CoreGraphics
import Foundation

public enum CommandKeyStyle {

    // MARK: - Geometry

    /// Shared command and Space shape, chosen in native previews. Hit frames stay unchanged.
    public static let cornerRadius: CGFloat = 12

    /// The size a command key's visible plate is drawn at.
    ///
    /// Grid edge commands use the matching Emoji bottom-bar or Delete face width.
    public static let visualSize: CGFloat = VoiceOnlyKeyboardPolicy.bottomBarVisualHeight

    /// The visible plate for a command key. Edge keys share Emoji Delete's
    /// outer inset; interior keys stay centred on their hit area.
    ///
    /// The hit area stays at its resolved size so nothing changes about what can be
    /// pressed; only the plate the user sees is standardised. Renderers reserve a
    /// neighbour gap; layout callers keep the full envelope for unchanged targets.
    public static func visualPlate(for hit: CGRect, surfaceWidth: CGFloat? = nil,
                                   neighborGap: CGFloat = 0) -> CGRect {
        let leading = surfaceWidth != nil && hit.minX <= KeyGridPlacement.edgeInset + 1
        let trailing = surfaceWidth.map { hit.maxX >= $0 - KeyGridPlacement.edgeInset - 1 } ?? false
        let reference = surfaceWidth.map {
            VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(
                width: max(0, $0 - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
                height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
            ))
        } ?? CGSize(width: visualSize, height: visualSize)
        // Keep the outer alignment, leaving the requested gap on the inner edge.
        let edgeInset = CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding)
        let edgeShift = leading ? max(0, edgeInset - hit.minX)
            : trailing ? max(0, hit.maxX - ((surfaceWidth ?? hit.maxX) - edgeInset)) : 0
        let width = max(0, min(reference.width,
                               hit.width + (surfaceWidth == nil ? 0 : KeyGridPlacement.edgeGap) - edgeShift)
                        - max(0, neighborGap))
        let height = max(0, min(reference.height, hit.height))
        let x: CGFloat
        if leading {
            x = edgeInset
        } else if let surfaceWidth, trailing {
            x = surfaceWidth - edgeInset - width
        } else {
            x = hit.midX - width / 2
        }
        return CGRect(x: x, y: hit.midY - height / 2,
                      width: width, height: height)
    }

    // MARK: - Glyph

    /// Point size and weight of a command key's system glyph.
    ///
    /// These were three different pairs — 16 semibold on the emoji page, 18 regular on
    /// the letter and symbol grids, 18 regular on the number pad — on keys that are
    /// otherwise identical. 16 semibold is the one that was already correct against
    /// the system keyboard's own delete icon.
    public static let glyphSize: CGFloat = 16
    public static let glyphWeight: KeyGlyphWeight = .semibold
    public static let textSize: CGFloat = 14
    public static let deleteSymbolName = "delete.backward"

    // MARK: - Press treatment

    /// Scale the plate is drawn at while held.
    public static let pressScale: CGFloat = 0.97
    /// Opacity of a held key, for renderers that can set one.
    public static let pressOpacity: CGFloat = 0.72
    /// Press-in and press-out durations.
    public static let pressDurationIn: TimeInterval = 0.08
    public static let pressDurationOut: TimeInterval = 0.16
    /// How much a plate is washed with the label colour when it is *lit* — engaged
    /// rather than held.
    ///
    /// Shift is the only key with this third state, and it needs one: a solid arrow
    /// on an unlit plate is what the resting key already looked like, so without a
    /// change to the plate there is nothing to see. Lighter than a press, because a
    /// press is a touch that is happening and this is a state that persists.
    public static let litWashAlpha: CGFloat = 0.28
    /// How much a held plate is washed with the label colour.
    ///
    /// The Core Graphics stand-in for `pressOpacity`. A renderer that owns the whole
    /// layer can just fade it; one drawing over a sibling `UIGlassEffect` cannot,
    /// because the material belongs to a different view. Fading a dark glass plate
    /// over a dark keyboard reads as a lightening, so the wash goes up rather than
    /// down, and the number is as small as still reads as a press.
    public static let pressWashAlpha: CGFloat = 0.18

    /// The plate as it should be drawn while held: scaled about its own centre.
    ///
    /// Scaling about the centre rather than insetting from the top-left is what makes
    /// a key look pressed instead of moved.
    public static func pressedPlate(_ rect: CGRect, pressed: Bool) -> CGRect {
        guard pressed, rect.width > 0, rect.height > 0 else { return rect }
        let width = rect.width * pressScale
        let height = rect.height * pressScale
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
