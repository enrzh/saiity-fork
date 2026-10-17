import Foundation

public enum KeyboardDictationIntent: String, Sendable, Equatable, CaseIterable {
    case record
    case prepare
}

/// Admission for the existing keyboard-to-app deep link; unrelated widget links stay separate.
public enum KeyboardDictationURL {
    public static func intent(from url: URL) -> KeyboardDictationIntent? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "saiity", components.host?.lowercased() == "dictate",
              components.user == nil, components.password == nil, components.port == nil,
              let items = components.queryItems else { return nil }
        let sources = items.filter { $0.name == "source" }
        guard sources.count == 1, sources.first?.value == "keyboard" else { return nil }
        // Existing keyboards omit intent or send values unknown to an older app.
        return items.contains { $0.name == "intent" && $0.value == "prepare" } ? .prepare : .record
    }
}
