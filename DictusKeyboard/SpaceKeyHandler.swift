// DictusKeyboard/SpaceKeyHandler.swift
import UIKit
import SyllivraKernel

/// Space inserts a space, after expanding a text replacement that ends right
/// before it. iOS Text Replacements come from the supplementary lexicon;
/// snippets saved by earlier versions of the app take precedence.
final class SpaceKeyHandler {
    static let shared = SpaceKeyHandler()

    /// iOS Text Replacements, refreshed each time the keyboard appears.
    var systemReplacements = SystemTextReplacements()

    func handleSpace(proxy: UITextDocumentProxy) {
        let context = proxy.documentContextBeforeInput ?? ""
        if let last = context.last, !last.isWhitespace, !last.isNewline {
            let word = lastWord(in: context)
            if let expansion = SnippetStore.expansion(for: word, from: AppGroup.defaults)
                ?? systemReplacements.expansion(for: word),
               case .ok(let deleteCount) = AutocorrectReplacement.check(context: context, word: word) {
                for _ in 0..<deleteCount { proxy.deleteBackward() }
                proxy.insertText(expansion)
                HapticFeedback.playInputClick()
            }
        }
        proxy.insertText(" ")
    }

    private func lastWord(in text: String) -> String {
        var word = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let substring { word = substring }
        }
        return word
    }
}
