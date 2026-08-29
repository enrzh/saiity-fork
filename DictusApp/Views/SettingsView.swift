// DictusApp/Views/SettingsView.swift
// iOS-style grouped settings list with preferences persisted via App Group.
import SwiftUI
import UIKit
import DictusCore

/// Settings screen: Dictus Pro, Transcription, Keyboard, and Pro Features.
///
/// WHY @AppStorage with App Group store:
/// Preferences need to be readable by both the main app AND the keyboard extension.
/// @AppStorage with the App Group suite writes to the shared UserDefaults container,
/// making preferences available across processes without any additional sync logic.
///
/// WHY grouped List style:
/// iOS standard settings pattern — users immediately recognize the familiar
/// grouped rows with section headers and footers.
struct SettingsView: View {

    @EnvironmentObject var proStatus: ProStatusManager

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var liveActivityEnabled = true

    /// Post-STT polish toggle (issue #141). Off by default — opt-in measurement at round 1.
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var polishEnabled = false

    #if DEBUG
    /// Debug-only: logs autocorrect decisions with user text to the debug log.
    /// This toggle only exists in DEBUG builds — the Release binary doesn't contain
    /// either this @AppStorage or the AutocorrectDebugLog code that reads it.
    @AppStorage(SharedKeys.autocorrectDebugLogging, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectDebugLogging = false
    #endif

    /// Tracks log export async operation for spinner display.
    /// Drives the paywall cover. Shared by the Dictus Pro row and every locked
    /// feature row: they open the same screen, so one flag serves both.
    @State private var showPaywall = false

    // MARK: - Body

    var body: some View {
        List {
            // Section 0: Dictus Pro — always first.
            // Gated behind PremiumFlags.paywallVisible until the first Pro
            // feature ships and ASC setup is done (#236, #79, #215).
            if PremiumFlags.paywallVisible {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.dictusAccent)
                            Text("sAiity Pro")
                                .foregroundColor(.primary)
                            Spacer()
                            if proStatus.isProActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.dictusSuccess)
                                    .accessibilityLabel("Pro active")
                            }
                            // A Button in a List draws no disclosure indicator,
                            // and this row still leads somewhere. Matching the
                            // system one by hand keeps the section reading like
                            // the rows around it.
                            listDisclosureIndicator
                        }
                    }
                }
            }

            // Section 1: Transcription
            Section {
                if PolishAvailability.isToggleVisible {
                    Toggle("Polish transcription", isOn: $polishEnabled)
                    polishStateFooter
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Dictation language is detected automatically.")
            }

            // Section 2: Clavier
            Section {
                Toggle("Live Activity", isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { _, enabled in
                        if !enabled {
                            LiveActivityManager.shared.stopStandbyActivity()
                        }
                    }
            } header: {
                Text("Keyboard")
            } footer: {
                // Only shown once the row is on: the keyboard drops it in landscape by
                // design (#331) and on iPad by design (#336), and without a word here either
                // one reads as a bug to the person who just turned it on.
                //
                // WHY one sentence covering both rather than a device-aware one, and why the
                // toggle stays visible on an iPad where it now does nothing: this target has
                // no device detection at all — `DeviceContext` and DeviceKit are linked to the
                // keyboard, not here, and `UIDevice.userInterfaceIdiom` reports `.phone` in
                // compatibility mode, which is the only way an iPad reaches this app. A second
                // copy of device detection in a second target, for a device class Dictus does
                // not target, costs more than a sentence that is simply true on both.
                if !liveActivityEnabled {
                    Text("Dynamic Island and Lock Screen notification are disabled.")
                }
            }

            // Section 3: Pro Features.
            // Gated behind PremiumFlags.paywallVisible (#236): while hidden,
            // the app must look like there is no subscription at all — no
            // locked rows, no PRO pills, no navigation path to PaywallView.
            // Pro toggles are also hidden: no user can be Pro while the
            // paywall is unreachable (no ASC product exists yet, #215).
            if PremiumFlags.paywallVisible {
                Section("Pro Features") {
                    ForEach(ProFeature.allCases, id: \.self) { feature in
                        if proStatus.isProActive {
                            // Unlocked: show toggle
                            Toggle(isOn: Binding(
                                get: { AppGroup.defaults.bool(forKey: feature.settingsKey) },
                                set: { AppGroup.defaults.set($0, forKey: feature.settingsKey) }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.dictusAccent)
                                    Text(LocalizedStringKey(feature.displayName))
                                }
                            }
                        } else {
                            // Locked: show lock + PRO pill, tap opens paywall
                            Button {
                                showPaywall = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.secondary)
                                    Text(LocalizedStringKey(feature.displayName))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.dictusAccent)
                                        .accessibilityHidden(true)
                                    Text("PRO")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                        .background(Color.dictusAccent)
                                        .clipShape(Capsule())
                                        .accessibilityLabel("Pro feature")
                                    listDisclosureIndicator
                                }
                            }
                        }
                    }
                }
            }

            #if DEBUG
            // Section: Developer (visible ONLY in Debug builds — not in Release/TestFlight/App Store).
            // WHY #if DEBUG: Code inside is compile-time excluded from production builds.
            // Impossible to accidentally ship a toggle that logs user text.
            Section {
                Toggle("Autocorrect debug logs", isOn: $autocorrectDebugLogging)
            } header: {
                Text("Developer")
            } footer: {
                if autocorrectDebugLogging {
                    Text("Warning: logs contain typed words and corrections. Debug builds only.")
                        .foregroundColor(.orange)
                } else {
                    Text("Logs autocorrect decisions for debugging. Off by default.")
                }
            }
            #endif

        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .paywallCover(isPresented: $showPaywall)
    }

    // MARK: - Private

    /// The chevron `NavigationLink` draws on a List row, for rows that open a
    /// cover instead and therefore have to draw it themselves.
    private var listDisclosureIndicator: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// Footer row under the polish toggle — surfaces the specific reason
    /// Apple Foundation Models is or isn't usable. When the state is `.available`
    /// no footer is shown (the toggle alone is enough).
    @ViewBuilder
    private var polishStateFooter: some View {
        let state = PolishAvailability.state
        if state != .available {
            VStack(alignment: .leading, spacing: 6) {
                Text(polishStateMessage(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if PolishAvailability.canOpenSystemSettings(for: state) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iPhone Settings")
                            .font(.caption.bold())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// User-facing explanation per availability state. Strings live in this
    /// view so Localizable.xcstrings can auto-detect them.
    private func polishStateMessage(for state: PolishAvailabilityState) -> String {
        switch state {
        case .available:
            return ""
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is required for polish. Enable it in iPhone Settings → Apple Intelligence & Siri. Apple requires Siri and your iPhone to use the same language — if Siri is in English and your iPhone is in French (or vice versa), Apple Intelligence stays off."
        case .modelNotReady:
            return "The Apple Intelligence model is downloading on your device. Try again in a few minutes."
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this device. Polish requires an iPhone 15 Pro / 15 Pro Max or newer."
        case .osTooOld:
            return "Polish requires iOS 26 or later."
        case .sdkMissing:
            return "Polish isn't available in this build of sAiity."
        case .other(let reason):
            return "Apple Intelligence is unavailable (\(reason))."
        }
    }

}
