import Foundation

/// Decides when the keyboard should foreground Dictus for model preparation.
///
/// The model can be available on disk while the app is loading it into RAM. In that state
/// the keyboard shows an explicit preparation action. The app's scene phase is deliberately
/// not used here: a keyboard is normally visible while DictusApp is in the background, and
/// treating that normal phase as unavailable would leave the button stuck on "Open sAiity".
public enum KeyboardModelPreparationPolicy {
    public static func shouldOpenApp(
        modelReady: Bool,
        modelLoadState: ModelLoadState,
        appPhase _: AppScenePhaseMarker
    ) -> Bool {
        // A missing model needs the app so it can download or install it.
        guard modelReady else { return true }

        // Keep the preparation action visible during an in-flight load, regardless
        // of whether the app is currently foregrounded or backgrounded.
        return modelLoadState == .loading
    }
}
