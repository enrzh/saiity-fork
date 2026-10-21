// tools/typo_finder.swift — lists web typos in a frequency list so dict_builder.py can leave
// them out of the spellcheck dictionary.
//
//     swift tools/typo_finder.swift DictusKeyboard/Resources/en_frequency.json en > tools/typos/en.tsv
//
// Norvig's web counts behind en_frequency.json include "teh", "adn" and "recieve". A word in
// the spellcheck dictionary counts as correct, so the keyboard never corrected them. A word is
// listed when macOS rejects it lowercased and capitalized (names stay) in every listed variant
// (regional spellings stay), and macOS would autocorrect it to a word of the same list that is
// at least five times as frequent and at most two edits away. Output is "typo<TAB>fix<TAB>ratio".
// The result depends on the Mac's spelling dictionaries, so the generated list is committed.
import AppKit
let args = CommandLine.arguments
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let raw = try JSONSerialization.jsonObject(with: data) as! [String: Int]
let language = args[2]
var freq: [String: Int] = [:]
for (word, count) in raw {
    let w = word.lowercased().trimmingCharacters(in: .whitespaces)
    guard !w.isEmpty, !w.contains(" "), !w.contains("-"), count > 0 else { continue }
    freq[w] = max(freq[w] ?? 0, count)
}
let checker = NSSpellChecker.shared
// US and British English are the two written standards; the smaller regional
// dictionaries accept stray misspellings ("teh" in en_SG, "seperate" in en_AU).
let variants = language == "en" ? ["en", "en_GB"] : [language]
precondition(variants.allSatisfy(checker.availableLanguages.contains), "No macOS spelling dictionary for \(language)")

func misspelled(_ text: String, in variant: String) -> Bool {
    checker.checkSpelling(of: text, startingAt: 0, language: variant, wrap: false,
                          inSpellDocumentWithTag: 0, wordCount: nil).location != NSNotFound
}
// The spelling server times out on its first requests and then answers "correct";
// warm it up so the most frequent words are judged like the rest.
for variant in variants {
    for _ in 0..<5 { _ = misspelled("teh", in: variant); Thread.sleep(forTimeInterval: 0.3) }
}
// Names are words when capitalized ("Mary"); regional spellings ("tyres",
// "practise") are words in another variant.
func isTypo(_ word: String) -> Bool {
    variants.allSatisfy { variant in
        misspelled(word, in: variant) && misspelled(word.capitalized, in: variant)
    }
}
// Optimal string alignment distance: insert, delete, substitute, swap neighbours.
func distance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
    var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { d[i][0] = i }
    for j in 0...b.count { d[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
            }
        }
    }
    return d[a.count][b.count]
}
// macOS's own automatic correction is the judge: it is what the system keyboard
// would do with the word. A correction that adds an apostrophe or a space
// ("youre", "alot") is left to the contraction and split handling instead.
func correction(_ word: String, in variant: String) -> String? {
    let whole = NSRange(location: 0, length: (word as NSString).length)
    return checker.correction(forWordRange: whole, in: word, language: variant, inSpellDocumentWithTag: 0)?.lowercased()
}
for (word, count) in freq.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) }) where isTypo(word) {
    let fixes = variants.map { correction(word, in: $0) }
    guard let fix = fixes[0], fixes.allSatisfy({ $0 != nil }),
          fix != word, fix.allSatisfy(\.isLetter),
          let fixCount = freq[fix], fixCount >= count * 5, distance(word, fix) <= 2,
          // Swiss German writes ss for ß.
          fix.replacingOccurrences(of: "ß", with: "ss") != word else { continue }
    print("\(word)\t\(fix)\t\(fixCount / count)")
}
