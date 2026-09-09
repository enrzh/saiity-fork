import Foundation

/// Decides when the keyboard should foreground Dictus for model preparation.
///
/// The model can be available on disk while the app is loading it into RAM. In that state
/// the keyboard shows an explicit preparation action. The app's scene phase is deliberately
/// not used here: a keyboard is normally visible while DictusApp is in the background, and
/// treating that normal phase as unavailable would leave the button stuck on "Open sAiity".
public enum KeyboardModelPreparationPolicy {
    /// Loading should never block the keyboard indefinitely after an app crash or
    /// a lost cross-process notification. This is longer than the normal large
    /// model warm-up window while still giving the next mic tap a recovery path.
    public static let maximumLoadingAge: TimeInterval = 10 * 60

    public static func isLoadingStateFresh(
        modelLoadState: ModelLoadState,
        modelLoadStartedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard modelLoadState == .loading else { return true }
        guard let modelLoadStartedAt else { return false }
        let age = now.timeIntervalSince(modelLoadStartedAt)
        return age >= 0 && age <= maximumLoadingAge
    }

    public static func shouldOpenApp(
        modelReady: Bool,
        modelLoadState: ModelLoadState,
        appPhase _: AppScenePhaseMarker,
        modelLoadStartedAt: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        // A missing model needs the app so it can download or install it.
        guard modelReady else { return true }

        // Keep the preparation action visible during an in-flight load, regardless
        // of whether the app is currently foregrounded or backgrounded.
        guard modelLoadState == .loading else { return false }
        return isLoadingStateFresh(
            modelLoadState: modelLoadState,
            modelLoadStartedAt: modelLoadStartedAt,
            now: now
        )
    }
}
