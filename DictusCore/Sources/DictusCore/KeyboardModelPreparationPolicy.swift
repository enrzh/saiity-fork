import Foundation

/// Decides when the keyboard should foreground Dictus for model preparation.
///
/// The model can be available on disk while the app is loading it into RAM. In that state
/// the keyboard shows an explicit preparation action. The app's scene phase is deliberately
/// not used here: a keyboard is normally visible while DictusApp is in the background, and
/// treating that normal phase as unavailable would leave the button stuck on "Open Syllivra".
public enum KeyboardModelPreparationPolicy {
    /// Loading should never block the keyboard indefinitely after an app crash or
    /// a lost cross-process notification. This is longer than the normal large
    /// model warm-up window while still giving the next mic tap a recovery path.
    public static let maximumLoadingAge: TimeInterval = 10 * 60

    /// Reads both the current JSON App Group representation and the legacy
    /// property-list array used by older releases. A stale format must not make
    /// a cached keyboard claim that sAiity needs to be opened again.
    public static func downloadedModelIDs(from value: Any?) -> [String] {
        if let data = value as? Data,
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        if let strings = value as? [String] {
            return strings
        }
        if let strings = value as? [NSString] {
            return strings.map(String.init)
        }
        return []
    }

    /// Repairs the legacy single-bit readiness contract when the app has already
    /// persisted a valid active/downloaded model pair. The keyboard cannot inspect
    /// the model files directly, so this is the strongest cross-process fallback
    /// available when `modelReady` was not refreshed by the app process.
    public static func effectiveModelReady(
        modelReady: Bool,
        activeModel: String?,
        downloadedModels: [String]
    ) -> Bool {
        guard !modelReady else { return true }
        guard let activeModel = activeModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !activeModel.isEmpty else { return false }
        return downloadedModels.contains(activeModel)
    }

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
        // `.ready` is the stronger signal: it means the active model is already
        // loaded in RAM. A stale `modelReady` value from an older app process must
        // not leave every keyboard instance stuck on "Open Syllivra".
        if modelLoadState == .ready {
            return false
        }

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
