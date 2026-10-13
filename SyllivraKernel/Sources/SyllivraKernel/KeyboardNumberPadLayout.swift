// SyllivraKernel/Sources/SyllivraKernel/KeyboardNumberPadLayout.swift
// Native-style 3×4 pad for number/phone/OTP host fields. The 123 symbols page
// stays on KeyboardSymbolsLayout.numbers.
import Foundation

/// Native-style 3×4 pad used when the host field asks for a number/phone keyboard.
public enum KeyboardNumberPadLayout {
    public enum Kind: Equatable {
        case insert(String, holdLetters: Bool = false)
        case delete
        case spacer
        /// Custom keyboards have no globe, so the empty `numberPad` slot is ABC.
        case letters
    }

    public struct Key: Equatable {
        public let kind: Kind
        public let width: Double

        public init(_ kind: Kind, width: Double = 1) {
            self.kind = kind
            self.width = width
        }
    }

    /// Four rows of three equal keys, matching the system number / decimal / phone pads.
    public static func rows(
        for style: HostFieldPolicy.NumberPadStyle,
        decimalSeparator: String = "."
    ) -> [[Key]] {
        let digits: [[Key]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"]
        ].map { row in row.map { Key(.insert($0)) } }

        let separator = decimalSeparator.isEmpty ? "." : decimalSeparator
        let bottom: [Key]
        switch style {
        case .digits:
            bottom = [Key(.letters), Key(.insert("0")), Key(.delete)]
        case .decimal:
            bottom = [Key(.insert(separator, holdLetters: true)), Key(.insert("0")), Key(.delete)]
        case .phone:
            // Native phone pads put `#` on the bottom-right; custom keyboards
            // still need backspace on that slot. Type `#` from the 123 page.
            // Hold `*` for ABC, matching hold-on-separator for decimal pads.
            bottom = [Key(.insert("*", holdLetters: true)), Key(.insert("0")), Key(.delete)]
        }
        return digits + [bottom]
    }
}
