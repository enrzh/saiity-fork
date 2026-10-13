#if os(iOS)
import Foundation

/// Builds Live Activity content from the dictation preference, not from
/// microphone warmup. Audio readiness stays a separate fact.
public enum LiveActivityStateMapper {
    public static func standby(
        detectionMuted: Bool,
        defaults: UserDefaults
    ) -> DictusLiveActivityAttributes.ContentState {
        DictusLiveActivityAttributes.ContentState(
            phase: .standby,
            detectionMuted: detectionMuted,
            serviceEnabled: KeyboardDictationService.isEnabled(in: defaults)
        )
    }
}
#endif
