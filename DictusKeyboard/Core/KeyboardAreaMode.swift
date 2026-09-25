import Foundation

/// The single value describing what the keyboard extension's keyboard area presents.
///
/// Before this was three independent flags spread over two layers: a SwiftUI
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
public enum KeyboardAreaMode: String, Equatable, CaseIterable, Sendable {
    /// The idle dictation surface with the toolbar visible.
    case keys
    /// The native-style letter keyboard, opened explicitly from the dictation board.
    case letters
    case emoji
    case panel
    /// Native-style 3×4 number pad for `numberPad` / `decimalPad` / `phonePad` / OTP.
    case numberPad
    /// The recording overlay fills the whole area, toolbar included.
    case recording

    public var usesVoiceActionControls: Bool {
        self == .keys || self == .recording
    }

    public var modeControlTitle: String {
        switch self {
        case .keys, .letters, .recording: return "123"
        case .emoji, .panel, .numberPad: return "ABC"
        }
    }

    /// Toggles the symbols surface from the keyboard's ABC/123 action.
    public static func toggledPanel(from current: KeyboardAreaMode) -> KeyboardAreaMode {
        current == .panel ? .keys : .panel
    }

    /// Destination for the 123 control. Numeric host fields return to the 3×4
    /// pad; every other field still opens the symbols page.
    public static func numbersMode(prefersNumberPad: Bool) -> KeyboardAreaMode {
        prefersNumberPad ? .numberPad : .panel
    }

    /// Surface to open when the keyboard appears, or when the host field type
    /// changes. Number/phone fields open the 3×4 pad, not the 123 symbols page.
    public static func openingMode(
        prefersNumberPad: Bool,
        defaultMode: DefaultKeyboardMode
    ) -> KeyboardAreaMode {
        if prefersNumberPad { return .numberPad }
        switch defaultMode {
        case .dictationBoard: return .keys
        case .keyboard: return .letters
        }
    }

    /// The mode after a dictation status change.
    ///
    /// A dictation owns the entire keyboard area while it is in flight. Leaving
    /// it returns to the idle voice surface.
    public static func resolving(
        status: DictationStatus,
        current: KeyboardAreaMode
    ) -> KeyboardAreaMode {
        if status.ownsKeyboardArea { return .recording }
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
        case .requested, .recording: return true
        case .transcribing, .processing, .idle, .ready, .failed: return false
        }
    }
}