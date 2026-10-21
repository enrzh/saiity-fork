// SyllivraKernel/Sources/SyllivraKernel/KeyboardDeletion.swift
import Foundation

/// Pure deletion policy shared by every keyboard surface.
///
/// A held backspace should remove the complete token immediately before the
/// caret, including the separator that leads into it. Keeping this calculation
/// in SyllivraKernel makes the behavior identical for UIKit and SwiftUI and keeps it
/// independently testable without constructing a text input proxy.
public enum KeyboardDeletion {
    public static let repeatDelay: TimeInterval = 0.5
    public static let repeatInterval: TimeInterval = 0.1
    public static let wordRepeatDelay: TimeInterval = 2.5
    public static let cursorHoldDuration: TimeInterval = 0.3
    public static let holdRecognitionDuration: TimeInterval = 0.35
    public static let dictationHoldRecognitionDuration: TimeInterval = 0.15
    /// Extra audio retained after a hold-to-dictate release. The UI enters its
    /// finishing state immediately; the app receives the stop request after this
    /// short tail so final words are less likely to be clipped.
    public static let dictationReleaseTailDuration: TimeInterval = 1.0
    public static let touchUpSuppressionDuration: TimeInterval = 0.12

    public enum RepeatAction: Equatable, Sendable {
        case character
        case word
    }

    public static func repeatsWords(after heldDuration: TimeInterval) -> Bool {
        heldDuration >= wordRepeatDelay
    }

    public static func repeatAction(after heldDuration: TimeInterval) -> RepeatAction {
        repeatsWords(after: heldDuration) ? .word : .character
    }
    /// Number of `deleteBackward()` calls needed to remove the previous word.
    ///
    /// `documentContextBeforeInput` is the only safe source of truth available to
    /// a keyboard extension. Whitespace at the caret is consumed first, then the
    /// preceding non-whitespace token. This matches the native keyboard's word
    /// deletion feel while remaining conservative at the start of a document.
    public static func previousWordLength(in context: String?) -> Int {
        guard let context, !context.isEmpty else { return 0 }

        var index = context.endIndex
        var count = 0
        var consumedTrailingWhitespace = false

        while index > context.startIndex {
            let previous = context.index(before: index)
            guard context[previous].isWhitespace else { break }
            count += 1
            index = previous
            consumedTrailingWhitespace = true
        }

        while index > context.startIndex {
            let previous = context.index(before: index)
            guard !context[previous].isWhitespace else { break }
            count += 1
            index = previous
        }

        // When the caret is directly after the word, consume its logical
        // separator as well. If trailing whitespace was already consumed, it
        // is the separator and must not be counted twice.
        if !consumedTrailingWhitespace, index > context.startIndex {
            let previous = context.index(before: index)
            if context[previous].isWhitespace {
                count += 1
            }
        }

        return count
    }
}
