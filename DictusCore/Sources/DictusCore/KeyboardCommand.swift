import Foundation

public enum KeyboardProxyAction: Equatable {
    case deleteBackward
    case insertText(String)
}

public enum KeyboardCommand {
    case delete
    case returnKey
    case at

    public var proxyAction: KeyboardProxyAction {
        switch self {
        case .delete: return .deleteBackward
        case .returnKey: return .insertText("\n")
        case .at: return .insertText("@")
        }
    }

    /// Routes through injected closures so the UIKit owner can be tested without
    /// constructing a text document proxy.
    public func perform(
        ifEnabled enabled: Bool = true,
        deleteBackward: () -> Void,
        insertText: (String) -> Void
    ) {
        guard enabled else { return }
        switch proxyAction {
        case .deleteBackward:
            deleteBackward()
        case .insertText(let value):
            insertText(value)
        }
    }
}
