import Foundation

/// Shared, platform-free definition of the two native symbols pages.
public enum KeyboardSymbolsLayout {
    public enum Kind: Equatable {
        case insert(String)
        case pageToggle
        case emoji
        case voice
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
        bottomRow(),
        actionRow()
    ]

    public static let symbols: [[Key]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { Key(.insert($0)) },
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·"].map { Key(.insert($0)) },
        bottomRow(),
        actionRow()
    ]

    private static func bottomRow() -> [Key] {
        [
            Key(.pageToggle, width: 1.5),
            Key(.insert("."), width: 0.9),
            Key(.insert(","), width: 0.9),
            Key(.insert("?"), width: 0.9),
            Key(.insert("!"), width: 0.9),
            Key(.insert("'"), width: 0.9),
            Key(.spacer, width: 1)
        ]
    }

    private static func actionRow() -> [Key] {
        [
            Key(.emoji, width: 1.5),
            Key(.voice, width: 1.5),
            Key(.spacer, width: 4),
            Key(.delete, width: 1.5),
            Key(.returnKey, width: 1.5)
        ]
    }
}
