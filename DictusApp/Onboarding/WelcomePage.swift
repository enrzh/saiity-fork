// DictusApp/Onboarding/WelcomePage.swift
// Step 1 of onboarding: animated waveform, wordmark, tagline, and "Commencer" button.
import SwiftUI
import DictusCore

/// Welcome page shown on first launch with animated brand waveform and tagline.
///
/// WHY BrandWaveform with processing (sinusoidal) animation:
/// A smooth traveling sine wave creates a polished first impression instead of
/// random jittery bars. The sinusoidal mode is inherently fluid (60fps via
/// TimelineView) and requires no Timer — simpler code, better visual result.
struct WelcomePage: View {
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Smooth sinusoidal waveform — same as the transcription processing animation
            BrandWaveform(
                maxHeight: 100,
                animation: reduceMotion ? .still : .sweep,
                isActive: !reduceMotion
            )
                .opacity(0.5)
                .padding(.bottom, 24)

            // "Dictus" wordmark
            Text("sAiity")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            // Tagline
            Text("Voice dictation, 100% offline")
                .font(.dictusBody)
                .foregroundStyle(.secondary)

            Spacer()

            // "Commencer" button
            Button(action: onNext) {
                Text("Get started")
                    .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            if AccessibilityMotionPolicy.permitsAnimation(reduceMotion: reduceMotion) {
                withAnimation(.easeIn(duration: 0.6).delay(0.5)) {
                    showContent = true
                }
            } else {
                showContent = true
            }
        }
    }
}
