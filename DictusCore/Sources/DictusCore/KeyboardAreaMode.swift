// DictusCore/Sources/DictusCore/KeyboardAreaMode.swift
// Single value describing what the keyboard extension's keyboard area presents.
import Foundation

/// What the voice-only keyboard surface is presenting.
///
/// Before #271 this was three independent flags spread over two layers: a SwiftUI
/// `@State` for the emoji picker in `KeyboardRootView`, a separate `Bool` for the
/// same picker in `KeyboardViewController` (kept in step through
/// `NotificationCenter`), and the recording overlay derived from `DictationStatus`.
/// Nothing in the type system stopped two of them being true at once, and the
/// layout code that reacted to them was a chain of negated guards that any new
/// full-area state had to be added to by hand — a state that was forgotten
/// collapsed to toolbar height while still being rendered.
///
/// With one value, mutual exclusion is a consequence of the type. Both layers
/// switch on it: SwiftUI to pick the branch it renders, the view controller to set
/// the hosting height and presentation state.
///
/// Lives in DictusCore rather than DictusKeyboard so the transition rule below is
/// unit-testable — the keyboard extension target has no test bundle. Same
/// reasoning as `DefaultKeyboardLayer` and `LayoutType`.
public enum KeyboardAreaMode: String, Equatable, CaseIterable, Sendable {
    /// The idle voice surface with the toolbar visible.
    case keys
    case emoji
    case panel
    /// The recording overlay fills the whole area, toolbar included.
    case recording

    public var usesVoiceActionControls: Bool {
        self == .keys || self == .recording
    }

    public var modeControlTitle: String {
        self == .keys || self == .recording ? "123" : "ABC"
    }

    /// Toggles the symbols surface from the keyboard's ABC/123 action.
    public static func toggledPanel(from current: KeyboardAreaMode) -> KeyboardAreaMode {
        current == .panel ? .keys : .panel
    }

    /// The mode after a dictation status change.
    ///
    /// A dictation owns the entire keyboard area while it is in flight. Leaving
    /// it returns to the idle voice surface.
    public static func resolving(
        status: DictationStatus,
        current: KeyboardAreaMode
    ) -> KeyboardAreaMode {
        if status.ownsKeyboardArea {
            return .recording
        }
        return current == .recording ? .keys : current
    }
}

public extension DictationStatus {
    /// Whether a live capture currently owns the keyboard area.
    ///
    /// Only `.requested` and `.recording` lock the surface: the user is holding
    /// the microphone. Transcription and cleanup continue in the background so
    /// emoji / 123 remain reachable, matching the native dictation keyboard.
    var ownsKeyboardArea: Bool {
        switch self {
        case .requested, .recording:
            return true
        case .transcribing, .processing, .idle, .ready, .failed:
            return false
        }
    }
}
