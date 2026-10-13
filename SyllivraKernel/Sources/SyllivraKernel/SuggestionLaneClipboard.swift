// SyllivraKernel/Sources/SyllivraKernel/SuggestionLaneClipboard.swift
import Foundation

/// Clipboard / OTP preview shown in the keyboard suggestion lane.
/// Keyboard extensions cannot receive system AutoFill suggestions, so this
/// surfaces the pasteboard after an explicit full-access read.
public struct SuggestionLaneClipboardItem: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case oneTimeCode
        case text
    }

    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let insertValue: String

    public var isOneTimeCode: Bool { kind == .oneTimeCode }

    public init(kind: Kind, title: String, subtitle: String, insertValue: String) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.insertValue = insertValue
    }

    public static func make(clipboardText: String?, isOneTimeCodeField: Bool) -> Self? {
        guard let raw = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let collapsed = raw
            .split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
        let preview = String(collapsed.prefix(64))
        if isOneTimeCodeField || looksLikeOneTimeCode(raw) {
            return Self(
                kind: .oneTimeCode,
                title: preview,
                subtitle: "Insert code",
                insertValue: raw
            )
        }
        return Self(
            kind: .text,
            title: preview,
            subtitle: "Paste",
            insertValue: raw
        )
    }

    /// Picks the first usable text representation from a pasteboard snapshot.
    /// The keyboard target supplies the UIKit values; this keeps the choice testable.
    public static func resolvedText(string: String?, strings: [String]?, urlString: String?) -> String? {
        if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        if let strings {
            for item in strings where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return item
            }
        }
        if let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return urlString
        }
        return nil
    }

    public static func looksLikeOneTimeCode(_ value: String) -> Bool {
        let compact = value.filter { !$0.isWhitespace && $0 != "-" }
        guard (4...8).contains(compact.count) else { return false }
        return compact.allSatisfy(\.isNumber)
    }
}
