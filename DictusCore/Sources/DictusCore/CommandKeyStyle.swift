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

    /// Corner radius of a command key's glass plate.
    ///
    /// 18, which on a 43pt plate is a generously rounded shape — close to a pill
    /// without being one. This is the product's radius, and it is what the whole
    /// family shares: the letter row's shift and delete, the 123/#+= row's two
    /// controls, the number pad's delete, the bottom bar, and the emoji page's
    /// delete.
    ///
    /// It was briefly 11, on the reading that the platform draws these as rounded
    /// squares. That reading came from a 56×50pt crop and does not survive checking:
    /// calibrating the measurement against known radii shows that 11, 15, 18 and
    /// 21.5 all predict corner insets within about a point of each other at this
    /// scale, which is well inside the noise. So the platform's exact radius is not
    /// something that crop can establish, and changing the product's look on a
    /// measurement that cannot tell 11 from 18 was wrong. It is 18 because that is
    /// the shape this keyboard is meant to have.
    public static let cornerRadius: CGFloat = 18

    /// The radius that makes a plate a full pill: half its height.
    ///
    /// For the space bar, which is the one key that is a pill rather than a rounded
    /// command shape — it is wide, so a full pill costs it nothing visually.
    public static func pillRadius(forHeight height: CGFloat) -> CGFloat {
        max(0, height / 2)
    }

    /// The size a command key's visible plate is drawn at.
    ///
    /// Grid edge commands use the matching Emoji bottom-bar or Delete face width.
    public static let visualSize: CGFloat = VoiceOnlyKeyboardPolicy.bottomBarVisualHeight

    /// The visible plate for a command key. Edge keys share Emoji Delete's
    /// outer inset; interior keys stay centred on their hit area.
    ///
    /// The hit area stays at its resolved size so nothing changes about what can be
    /// pressed; only the plate the user sees is standardised.
    public static func visualPlate(for hit: CGRect, surfaceWidth: CGFloat? = nil) -> CGRect {
        let leading = surfaceWidth != nil && hit.minX <= KeyGridPlacement.edgeInset + 1
        let trailing = surfaceWidth.map { hit.maxX >= $0 - KeyGridPlacement.edgeInset - 1 } ?? false
        let reference = surfaceWidth.map {
            VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(
                width: max(0, $0 - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
                height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
            ))
        } ?? CGSize(width: visualSize, height: visualSize)
        // Spend the pinned row's empty gap, accounting for the face's edge
        // alignment so a wide landscape command never covers its neighbour.
        let edgeInset = CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding)
        let edgeShift = leading ? max(0, edgeInset - hit.minX)
            : trailing ? max(0, hit.maxX - ((surfaceWidth ?? hit.maxX) - edgeInset)) : 0
        let width = max(0, min(reference.width,
                               hit.width + (surfaceWidth == nil ? 0 : KeyGridPlacement.edgeGap) - edgeShift))
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
    public static let pressScale: CGFloat = 0.94
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
