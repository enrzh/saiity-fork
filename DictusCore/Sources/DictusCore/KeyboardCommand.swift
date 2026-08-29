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
}
