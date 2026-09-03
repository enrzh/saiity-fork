import Foundation

/// Long-press extras for the 123 / symbols pages, matching the native iOS keyboard.
public enum SymbolKeyVariants {
    /// Alternate characters shown after the base key. Keys with no extras omit a popup.
    public static let extras: [String: [String]] = [
        "0": ["°"],
        "2": ["²"],
        "3": ["³"],
        "-": ["–", "—", "•"],
        "/": ["\\"],
        "$": ["¢", "€", "£", "¥", "₩", "₱"],
        "&": ["§"],
        "\"": ["“", "”", "«", "»", "„"],
        ".": ["…"],
        "?": ["¿"],
        "!": ["¡"],
        "'": ["‘", "’", "`", "′"],
        "%": ["‰"],
        "=": ["≠", "≈"],
        "+": ["±"],
        "<": ["≤", "«"],
        ">": ["≥", "»"],
        "€": ["¢", "$", "£", "¥", "₩", "₱"],
        "£": ["¢", "$", "€", "¥", "₩", "₱"],
        "¥": ["¢", "$", "€", "£", "₩", "₱"],
        "·": ["•"],
        "*": ["•", "×"],
        "#": ["№"],
        "^": ["↑"],
        "~": ["˜"],
        "_": ["–"],
        "|": ["¦"]
    ]

    /// Popup options for `key`, base character first. Empty when the native keyboard
    /// has no long-press extras.
    public static func options(for key: String) -> [String] {
        guard let extras = extras[key], !extras.isEmpty else { return [] }
        var options = [key]
        for extra in extras where extra != key {
            options.append(extra)
        }
        return options
    }
}
