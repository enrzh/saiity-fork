#if os(iOS)
import SwiftUI
import UIKit

/// The same Icon Composer artwork in the app, keyboard and Live Activity.
public struct DictusLogo: View {
    public var height: CGFloat
    public var foregroundOnly: Bool
    public var tint: Color
    public init(height: CGFloat = 80, foregroundOnly: Bool = false, tint: Color = .saiityAction) {
        self.height = height
        self.foregroundOnly = foregroundOnly
        self.tint = tint
    }
    public var body: some View {
        Group {
            if foregroundOnly {
                VoiceRibbons().fill(tint)
            } else {
                Image("SaiityBrand", bundle: .module).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.22))
            }
        }
            .frame(width: height, height: height)
            .accessibilityLabel("Syllivra")
    }

    /// UIKit command faces use the same vector, rendered once per glyph size.
    public static func templateImage(height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: height, height: height)).image { context in
            context.cgContext.addPath(VoiceRibbons().path(in: CGRect(x: 0, y: 0, width: height, height: height)).cgPath)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fillPath()
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// The same three vector layers as the Icon Composer document, without its
/// app-icon background. WidgetKit can render this even when raster assets fail.
private struct VoiceRibbons: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 232, y: 394, width: 128, height: 300), cornerSize: CGSize(width: 64, height: 64))
        path.addRoundedRect(in: CGRect(x: 448, y: 214, width: 128, height: 540), cornerSize: CGSize(width: 64, height: 64))
        path.move(to: CGPoint(x: 728, y: 318))
        path.addCurve(to: CGPoint(x: 792, y: 382), control1: CGPoint(x: 763.35, y: 318), control2: CGPoint(x: 792, y: 346.65))
        path.addLine(to: CGPoint(x: 792, y: 658))
        path.addCurve(to: CGPoint(x: 728, y: 722), control1: CGPoint(x: 792, y: 693.35), control2: CGPoint(x: 763.35, y: 722))
        path.addLine(to: CGPoint(x: 724, y: 722))
        path.addLine(to: CGPoint(x: 664, y: 784))
        path.addLine(to: CGPoint(x: 664, y: 382))
        path.addCurve(to: CGPoint(x: 728, y: 318), control1: CGPoint(x: 664, y: 346.65), control2: CGPoint(x: 692.65, y: 318))
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: -232, y: -214))
            .applying(CGAffineTransform(scaleX: rect.width / 560, y: rect.height / 570))
    }
}
#endif
