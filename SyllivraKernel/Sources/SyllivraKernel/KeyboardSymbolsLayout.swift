import Foundation

/// Shared, platform-free definition of the two native symbols pages.
public enum KeyboardSymbolsLayout {
    public enum Kind: Equatable {
        case insert(String)
        case pageToggle
        case emoji
        case voice
        case space
        case delete
        case returnKey
        case spacer
    }

    public struct Key: Equatable {
        public let kind: Kind
        public let width: Double

        public init(_ kind: Kind, width: Double = 1) {
            self.kind = kind
            self.width = width
        }
    }

    public static let numbers: [[Key]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { Key(.insert($0)) },
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""].map { Key(.insert($0)) },
        bottomRow()
    ]

    public static let symbols: [[Key]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { Key(.insert($0)) },
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·"].map { Key(.insert($0)) },
        bottomRow()
    ]

    private static func bottomRow() -> [Key] {
        [
            // Give the two glass command keys the same visual width as the
            // dictation board's delete/return controls. The punctuation keys
            // keep the remaining row compact without sharing their hit target.
            Key(.pageToggle, width: 2.25),
            Key(.insert(".")),
            Key(.insert(",")),
            Key(.insert("?")),
            Key(.insert("!")),
            Key(.insert("'")),
            // Native symbols keyboards put Delete above Return. Delete therefore
            // belongs to the last symbol row while Return remains in the shared bar.
            Key(.delete, width: 2.25)
        ]
    }
}
