// DictusApp/Views/ModelLoadingOverlay.swift
// Full-screen blocking overlay shown while a model is downloading, compiling
// for the Neural Engine, or being loaded into RAM. Issue #144.
import SwiftUI
import DictusCore

/// Full-screen cover that surfaces long-running model preparation work to the user.
///
/// Why this exists:
/// Whisper turbo (~954 MB) takes ~2 min of one-off Core ML compilation on a 15 Pro Max
/// and a couple of seconds to load into RAM after each cold start. Without a blocking UI
/// the user could mistake the wait for a frozen app, tap the keyboard mic mid-load,
/// and trigger a `Swift.CancellationError` cascade (issue #144). The overlay refuses
/// any further model interaction until `modelLoadState == .ready`.
///
/// The overlay observes two signals to decide which copy to show:
/// 1. `ModelManager.modelStates[id]` — `.downloading`, `.prewarming`, `.ready`
/// 2. `ModelManager.modelLoadState` (mirrored from the App Group via Combine) —
///    `.loading` once `DictationCoordinator.preloadActiveModel` is in flight.
struct ModelLoadingOverlay: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject private var coordinator = DictationCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Identifier of the model the user just acted on (download or select).
    /// Drives the phase logic and which copy is shown.
    let modelIdentifier: String

    /// Two-way binding controlled by the parent. The overlay flips it to false
    /// once the model becomes ready so the cover dismisses itself.
    @Binding var isPresented: Bool

    /// The user-facing flow that caused preparation to be shown.
    let context: ModelPreparationContext

    @State private var showCompletion = false
    @State private var activeContext: ModelPreparationContext

    /// Tracks whether we have ever observed an active prep phase (queued,
    /// downloading, compiling, or loading). Without this, the overlay would auto-dismiss
    /// when presented synchronously by the parent before `downloadModel`
    /// has had a chance to flip `modelStates[id]` from `.notDownloaded` to
    /// `.downloading` — the onboarding race that surfaced after f5ba7ab.
    @State private var hasSeenWorkPhase = false

    private enum Phase {
        case downloading
        case compiling
        case loading
        case ready
    }

    init(
        modelManager: ModelManager,
        modelIdentifier: String,
        context: ModelPreparationContext = .modelSelection,
        isPresented: Binding<Bool>
    ) {
        self.modelManager = modelManager
        self.modelIdentifier = modelIdentifier
        self.context = context
        self._isPresented = isPresented
        self._activeContext = State(initialValue: context)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DictusLogo(height: 52)
                SaiityPageHeader(title: "Preparing your voice model",
                                 subtitle: "Keep Syllivra open until preparation finishes.")
                modelTitleHeader
                VStack(alignment: .leading, spacing: 24) {
                    phaseRow("Download", detail: "Save the voice model on this iPhone.", phase: .downloading, index: 0)
                    phaseRow("Prepare", detail: "Optimize it for your device.", phase: .compiling, index: 1)
                    phaseRow("Activate", detail: "Load the model for dictation.", phase: .loading, index: 2)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                if showCompletion { completionView } else { activeView }
                stayOnPageNotice
            }
            .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: .dictusModelLoadStateChanged)) { _ in
            checkForCompletion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusKeyboardPreparationRequested)) { _ in
            activeContext = .keyboardColdStart
        }
        .onChange(of: currentModelState) { _, _ in
            checkForCompletion()
        }
        .onChange(of: coordinator.status) { _, _ in
            checkForCompletion()
        }
        .onChange(of: coordinator.keyboardSessionEnabled) { _, _ in
            checkForCompletion()
        }
        .onChange(of: coordinator.isPreparingKeyboardSession) { _, _ in
            // The model may already be ready, so microphone activation does not
            // necessarily emit a model-load-state change.
            checkForCompletion()
        }
        .onAppear {
            checkForCompletion()
        }
    }

    // MARK: - Sub-views

    private var modelTitleHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ModelInfo.forIdentifier(modelIdentifier)?.displayName ?? modelIdentifier)
                    .font(.title2.weight(.semibold))
                Text(showCompletion ? "Ready" : phaseLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: showCompletion ? "checkmark.circle.fill" : "cpu")
                .font(.largeTitle).foregroundStyle(.tint)
        }
    }

    private var phaseIndex: Int {
        if showCompletion { return 3 }
        switch currentPhase {
        case .downloading: return 0
        case .compiling: return 1
        case .loading: return 2
        case .ready: return 3
        }
    }

    private func phaseRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, phase: Phase, index: Int) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(index <= phaseIndex ? 0.15 : 0.04))
                if index < phaseIndex {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)").font(.headline).foregroundStyle(index == phaseIndex ? Color.accentColor : .secondary)
                }
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(index < phaseIndex ? "Complete" : index == phaseIndex ? "In progress" : "Waiting")
    }

    @ViewBuilder
    private var activeView: some View {
        VStack(spacing: 24) {
            if currentPhase == .downloading,
               let progress = modelManager.downloadProgress[modelIdentifier] {
                VStack(spacing: 6) {
                    ProgressView(value: Double(progress), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(maxWidth: 240)
                    Text(progressLabel(progress))
                        .font(.dictusCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Download progress"))
                    // Moving byte counter — reads as alive even while the
                    // percentage crawls through the 445 MB Encoder file (#207).
                    if let bytes = modelManager.downloadByteInfo[modelIdentifier] {
                        Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                            .font(.dictusCaption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Text(phaseLabel).font(.headline)
            if currentPhase != .downloading { ProgressView() }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Model ready")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            if activeContext.isPrepareOnly {
                Text("Return to your app and hold the keyboard microphone to dictate.")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var stayOnPageNotice: some View {
        VStack(spacing: 8) {
            Text(explanationText)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !(showCompletion && activeContext.isPrepareOnly) {
                Text(activeContext.isPrepareOnly
                     ? "Please wait for preparation to finish."
                     : "Please stay on this page — do not leave the app.")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                     .multilineTextAlignment(.center)
                     .padding(.horizontal, 48)
            }
            if activeContext.isPrepareOnly {
                preparationSteps
                    .padding(.top, 8)
            }
        }
    }

    private var preparationSteps: some View {
        VStack(alignment: .leading, spacing: 5) {
            preparationStep("1", "Keep Syllivra open while the model loads.")
            preparationStep("2", "Wait for the model and microphone to be ready.")
            preparationStep("3", "Return to your app. Hold the microphone to speak and release to insert your words.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
    }

    private func preparationStep(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanationText: LocalizedStringKey {
        switch activeContext {
        case .onboarding:
            return "Syllivra prepares your transcription model for offline dictation."
        case .modelSelection:
            return "This preparation may take a moment and is usually not needed for every dictation."
        case .keyboardColdStart:
            return "Keyboard dictation keeps the microphone ready in the background. Idle audio is discarded. Disable it in Syllivra or the Live Activity; it also ends after 10 idle minutes."
        }
    }

    // MARK: - Phase logic

    private var currentModelState: ModelState {
        modelManager.modelStates[modelIdentifier] ?? .notDownloaded
    }

    private var currentPhase: Phase {
        let raw = rawPhase
        if activeContext.isPrepareOnly && raw == .ready && !showCompletion {
            return .loading
        }
        // While we have not yet seen a real work phase, treat `.ready` as the
        // initial download phase so the copy doesn't briefly flash "ready"
        // before the parent's async download Task starts. This is the seam
        // that fixes the onboarding presentation race (commit f5ba7ab follow-up).
        if !hasSeenWorkPhase && raw == .ready {
            return .downloading
        }
        return raw
    }

    private var rawPhase: Phase {
        switch currentModelState {
        case .downloading:
            return .downloading
        case .prewarming:
            return .compiling
        case .ready:
            switch modelManager.modelLoadState {
            case .loading:
                return .loading
            case .ready:
                return .ready
            case .idle:
                // Defensive: model is ready on disk but no load is in flight.
                // Treat as ready so the overlay can dismiss.
                return .ready
            }
        case .notDownloaded, .error:
            return .ready
        }
    }

    private var phaseLabel: LocalizedStringKey {
        switch currentPhase {
        case .downloading: return "Downloading"
        case .compiling: return "Optimizing"
        case .loading: return "Loading"
        case .ready: return "Ready"
        }
    }

    private func progressLabel(_ progress: Float) -> String {
        "\(Int(progress * 100))%"
    }

    private func checkForCompletion() {
        if activeContext.isPrepareOnly && coordinator.status == .failed {
            isPresented = false
            return
        }
        // A failed download must dismiss the cover immediately — without this,
        // `.error` falls into rawPhase's `.ready` mapping below and flashes the
        // "Model ready" celebration on a failure (issue #207). The parent view
        // surfaces the error message once the cover is gone.
        if case .error = currentModelState {
            isPresented = false
            return
        }
        if case .notDownloaded = currentModelState, hasSeenWorkPhase {
            isPresented = false
            return
        }
        // Latch the work-phase flag the first time we observe real activity.
        // We read `rawPhase` here (not the user-facing `currentPhase`) because
        // the latter masquerades the initial `.ready` state as `.downloading`
        // until this flag flips, which would cause an infinite loop.
        if rawPhase != .ready {
            hasSeenWorkPhase = true
            return
        }
        // Model readiness alone must not dismiss microphone preparation. Check
        // errors and latch model work first so failures cannot strand this cover.
        if activeContext.isPrepareOnly {
            guard coordinator.keyboardSessionEnabled && coordinator.isEngineRunning
                    && coordinator.isKeyboardModelReady else { return }
        }
        // The model is ready, but if we have never seen any actual work happen
        // yet, the parent likely just opened the overlay and the state will
        // imminently flip to `.downloading`. Keep the cover up.
        let preparationWasAlreadyReady = activeContext.isPrepareOnly
            && currentModelState == .ready
            && modelManager.modelLoadState == .ready
        guard hasSeenWorkPhase || preparationWasAlreadyReady else {
            return
        }
        guard !showCompletion else { return }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            showCompletion = true
        }

        // Brief celebration moment before the cover slides away.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                isPresented = false
            }
        }
    }
}

#Preview("Downloading — light") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .downloading
            m.downloadProgress["openai_whisper-large-v3_turbo_954MB"] = 0.42
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.light)
}

#Preview("Compiling — dark") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .prewarming
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
