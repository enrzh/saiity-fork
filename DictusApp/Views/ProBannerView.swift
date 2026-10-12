// DictusApp/Views/ProBannerView.swift
// Compact native list row for HomeView, hidden when Pro is active.
import SwiftUI
import DictusCore

/// Compact Pro action at the bottom of HomeView.
///
/// WHY a separate view:
/// Keeps HomeView clean and makes the banner independently testable.
/// The banner has its own visibility logic (hidden when Pro active)
/// and navigation target (pushes PaywallView).
struct ProBannerView: View {
    @EnvironmentObject var proStatus: ProStatusManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showPaywall = false

    var body: some View {
        if !proStatus.isProActive {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Syllivra Pro")
                            .font(.body.weight(.medium))
                        Text("AI reformulation, history & more")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale))
            .animation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion), value: proStatus.isProActive)
            .paywallCover(isPresented: $showPaywall)
        }
    }
}
