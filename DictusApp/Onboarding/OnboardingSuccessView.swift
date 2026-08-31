// DictusApp/Onboarding/OnboardingSuccessView.swift
// Full-screen success overlay shown after transcription test completes.
import SwiftUI
import DictusCore

/// Apple Pay-style animated success screen at the end of onboarding.
///
/// WHY a dedicated view instead of inline in TestRecordingPage:
/// The success screen replaces the entire recording view with a celebration overlay.
/// Keeping it in its own file follows the project's single-responsibility convention
/// (one file = one responsibility) and makes it reusable if needed elsewhere.
///
/// WHY spring animation for checkmark:
/// The overshoot (scale 0 -> 1.1 -> 1.0) with spring physics mimics Apple's
/// success checkmark from Apple Pay and other system confirmations. Users
/// recognize this pattern as "you're done" without reading any text.
struct OnboardingSuccessView: View {
    let onComplete: () -> Void

    @State private var checkmarkScale: CGFloat = 0
    @State private var showText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated checkmark circle
                ZStack {
                    Circle()
                        .fill(Color.dictusSuccess)
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(checkmarkScale)
                .padding(.bottom, 32)

                // Title and subtitle (fade in after checkmark)
                VStack(spacing: 12) {
                    Text("You're all set!")
                        .font(.dictusHeading)
                        .foregroundStyle(.primary)

                    Text("sAiity is set up and ready to use")
                        .font(.dictusBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(showText ? 1 : 0)

                Spacer()

                // Commencer button (same style as other onboarding pages)
                Button(action: onComplete) {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            if reduceMotion {
                checkmarkScale = 1
                showText = true
                return
            }
            // Step 1: Spring the checkmark in (0 -> 1.1 -> 1.0)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
            }
            // Step 2: Fade in text + button after checkmark lands
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}
