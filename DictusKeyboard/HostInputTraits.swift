// DictusKeyboard/HostInputTraits.swift
// Maps the host text field's UITextInputTraits (read from UITextDocumentProxy)
// to the pure HostFieldPolicy decision in DictusCore (issue #200).
//
// WHY this split: UIKeyboardType/UITextContentType only exist in UIKit, but the
// policy logic must be unit-testable in DictusCoreTests (no UIKit on macOS).
// This file is the thin, untestable UIKit shim; the tested logic is in DictusCore.

import UIKit
import DictusCore

enum HostInputTraits {

    /// Reads the proxy's traits and evaluates the field policy.
    ///
    /// NOTE: traits are only accurate once the host connection exists
    /// (viewWillAppear onward) — same caveat as needsInputModeSwitchKey.
    /// UITextInputTraits members are optional ObjC requirements, hence the
    /// optional chaining with permissive defaults (missing trait = normal field).
    static func policy(for proxy: UITextDocumentProxy) -> HostFieldPolicy {
        HostFieldPolicy.evaluate(
            keyboard: keyboardKind(proxy.keyboardType),
            content: contentKind(proxy.textContentType),
            autocorrectionDisabled: proxy.autocorrectionType == .no,
            spellCheckingDisabled: proxy.spellCheckingType == .no,
            isSecureEntry: proxy.isSecureTextEntry ?? false
        )
    }

    static func isOneTimeCodeField(for proxy: UITextDocumentProxy) -> Bool {
        proxy.textContentType == .oneTimeCode
    }

    static func prefersNumberPad(for proxy: UITextDocumentProxy) -> Bool {
        HostFieldPolicy.prefersNumberPad(
            keyboard: keyboardKind(proxy.keyboardType),
            content: contentKind(proxy.textContentType)
        )
    }

    static func letterFieldKeys(for proxy: UITextDocumentProxy) -> HostFieldPolicy.LetterFieldKeys {
        var keys = HostFieldPolicy.letterFieldKeys(
            keyboard: keyboardKind(proxy.keyboardType),
            content: contentKind(proxy.textContentType)
        )
        switch proxy.returnKeyType {
        case .go: keys.returnTitle = "Go"
        case .search, .google, .yahoo: keys.returnTitle = "Search"
        case .send: keys.returnTitle = "Send"
        case .done: keys.returnTitle = "Done"
        case .next: keys.returnTitle = "Next"
        case .continue: keys.returnTitle = "Continue"
        case .join: keys.returnTitle = "Join"
        case .route: keys.returnTitle = "Route"
        case .emergencyCall: keys.returnTitle = "Call"
        default: break
        }
        return keys
    }

    static func prefersSymbolPage(for proxy: UITextDocumentProxy) -> Bool {
        HostFieldPolicy.prefersSymbolPage(keyboard: keyboardKind(proxy.keyboardType))
    }

    static func numberPadStyle(for proxy: UITextDocumentProxy) -> HostFieldPolicy.NumberPadStyle? {
        HostFieldPolicy.numberPadStyle(
            keyboard: keyboardKind(proxy.keyboardType),
            content: contentKind(proxy.textContentType)
        )
    }

    private static func keyboardKind(_ type: UIKeyboardType?) -> HostFieldPolicy.KeyboardKind {
        switch type {
        case .URL: return .url
        case .emailAddress: return .email
        case .webSearch: return .webSearch
        case .twitter: return .twitter
        case .numberPad, .asciiCapableNumberPad: return .numeric
        case .decimalPad: return .decimal
        case .phonePad: return .phone
        case .namePhonePad: return .namePhone
        case .asciiCapable: return .asciiCapable
        case .numbersAndPunctuation: return .symbols
        default: return .standard
        }
    }

    private static func contentKind(_ type: UITextContentType?) -> HostFieldPolicy.ContentKind {
        guard let type = type else { return .none }
        switch type {
        case .username: return .username
        case .password, .newPassword: return .password
        case .URL: return .url
        case .emailAddress: return .email
        case .oneTimeCode: return .oneTimeCode
        case .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix, .nickname, .organizationName, .jobTitle:
            return .name
        case .fullStreetAddress, .streetAddressLine1, .streetAddressLine2, .addressCity, .addressState, .addressCityAndState, .countryName:
            return .address
        case .postalCode: return .postalCode
        case .creditCardNumber: return .creditCard
        case .telephoneNumber: return .telephone
        default: return .other
        }
    }
}
