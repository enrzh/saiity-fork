import SwiftUI
import UIKit
import DictusCore

enum EmojiCategoryBarMetrics {
    static let railInset: CGFloat = 3
    static func slotWidth(trackWidth: CGFloat, sectionCount: Int) -> CGFloat {
        max(1, trackWidth - railInset * 2) / CGFloat(max(1, sectionCount))
    }

    static func index(atX x: CGFloat, trackWidth: CGFloat, sectionCount: Int) -> Int {
        guard sectionCount > 0, x.isFinite else { return 0 }
        let slot = slotWidth(trackWidth: trackWidth, sectionCount: sectionCount)
        return Int(min(max(floor((x - railInset) / slot), 0), CGFloat(sectionCount - 1)))
    }
}

/// A permanent category rail. Its native owner handles taps, drags and VoiceOver.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String

    var body: some View {
        GeometryReader { proxy in
            let slot = EmojiCategoryBarMetrics.slotWidth(trackWidth: proxy.size.width, sectionCount: sections.count)
            let height = max(0, proxy.size.height - VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset * 2)
            HStack(spacing: 0) {
                ForEach(sections) { section in
                    let selected = section.id == selectedCategoryID
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .symbolVariant(selected ? .fill : .none)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: slot, height: height)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(Color.primary).frame(width: min(14, slot), height: 1.5)
                            }
                        }
                }
            }
            .padding(.horizontal, EmojiCategoryBarMetrics.railInset)
            .frame(width: proxy.size.width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

typealias EmojiCategoryScrubControl = EmojiCategoryControl
