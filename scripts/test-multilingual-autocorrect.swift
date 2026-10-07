// Production prediction engine with bundled dictionaries, no audio/model downloads.
// swift scripts/test-multilingual-autocorrect.swift <QA-simulator> <derived-data>
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Pass simulator and derived-data paths") }
let simulator = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let keyboard = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
let program = #"""
import UIKit
import DictusCore
@testable import DictusKeyboard

func settle(_ engine: TextPredictionEngine) {
    let deadline = Date().addingTimeInterval(5)
    while engine.dictionaryLoadInFlight, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(!engine.dictionaryLoadInFlight, "Dictionary load did not settle")
}
func activeLanguage(_ engine: TextPredictionEngine) -> String {
    Mirror(reflecting: engine).children.first { $0.label == "language" }!.value as! String
}
func acceptanceIDs(_ engine: TextPredictionEngine) -> [String: ObjectIdentifier] {
    let tries = Mirror(reflecting: engine).children.first { $0.label == "acceptedWordTries" }!.value as! [String: AOSPTrieBridge]
    return tries.mapValues(ObjectIdentifier.init)
}
let defaults = AppGroup.defaults
let keys = [SharedKeys.language, SharedKeys.keyboardLanguageSelection, SharedKeys.keyboardLanguageMigrationVersion,
            SharedKeys.spokenLanguages,
            "dictus.userDictionary", "dictus.userDictionary.pending", "dictus.userDictionary.lastUsed",
            "dictus.userDictionary.prunedTrieDuplicates"]
let saved = keys.map { defaults.object(forKey: $0) }
defer {
    for (key, value) in zip(keys, saved) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    UserDictionary.shared.reload()
}
defaults.set("fr", forKey: SharedKeys.language)
KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
defaults.set([], forKey: SharedKeys.spokenLanguages)
defaults.set(true, forKey: "dictus.userDictionary.prunedTrieDuplicates")
let engine = TextPredictionEngine(bundle: Bundle(path: "KEYBOARD_BUNDLE")!)
engine.setSelectedLanguage("fr")
settle(engine)
precondition(engine.enabledDictionaryLanguages == ["fr"], "Empty preferences enabled the catalog")
for word in ["bonjor", "tres", "the", "bonjour"] { UserDictionary.shared.forget(word) }
precondition(engine.spellCheck("tres")?.correction == "très", "French accent repair was lost")
precondition(engine.spellCheck("bonjor")?.correction == "bonjour", "French typo repair was lost")
let french = acceptanceIDs(engine)["fr"]!

defaults.set(["en-US", "fr-FR", "en"], forKey: SharedKeys.spokenLanguages)
engine.setSelectedLanguage("fr")
settle(engine)
precondition(engine.enabledDictionaryLanguages == ["en", "fr"])
precondition(acceptanceIDs(engine)["fr"] == french, "Membership refresh reloaded the retained French map")
for word in ["the", "The", "THE", "bonjour", "Bonjour", "can", "dont", "tres"] {
    precondition(engine.spellCheck(word) == nil, "An exact enabled-language word was rewritten: \(word)")
    precondition(engine.spellCheck(word, previousWord: "je", isAtSentenceStart: false) == nil,
                 "Context re-ranking bypassed exact protection: \(word)")
}
// 'tres' is a valid Spanish word and is present in the shipped English trie;
// with that dictionary enabled it must remain exact, even during French typing.
precondition(engine.spellCheck("bonjor", previousWord: "dis")?.correction == "bonjour")
engine.setLanguage(forRecentText: "the updated invoice is ready to send tomorrow morning")
settle(engine)
precondition(activeLanguage(engine) == "en", "Confident enabled-language text did not select English")
engine.setLanguage(forRecentText: "Je vais envoyer la facture and the updated invoice demain matin")
settle(engine)
precondition(activeLanguage(engine) == "fr", "Mixed sentence retained the preceding single-language winner")
precondition(!engine.shouldAbstainFromPrediction(for: "Je vais envoyer la facture and the updated invoice demain matin"))
precondition(engine.spellCheck("bonjor")?.correction == "bonjour")
engine.setLanguage(forRecentText: "hello there")
settle(engine)
precondition(activeLanguage(engine) == "fr", "A short clause swapped the correction dictionary")
engine.setSelectedLanguage("en")
settle(engine)
engine.setLanguage(forRecentText: "the updated invoice is ready bonjour demain matin")
settle(engine)
precondition(activeLanguage(engine) == "en", "Mixed sentence did not keep selected English")
precondition(engine.spellCheck("bonjour") == nil)

defaults.set(["de-DE", "zh", "ru", "fr"], forKey: SharedKeys.spokenLanguages)
engine.setSelectedLanguage("en")
settle(engine)
precondition(engine.enabledDictionaryLanguages == ["de", "en", "fr"], "Unsupported or unselected dictionaries were mounted")
precondition(engine.spellCheck("Straße") == nil)
precondition(engine.spellCheck("Straße".decomposedStringWithCanonicalMapping) == nil)
precondition(engine.spellCheck("français".decomposedStringWithCanonicalMapping) == nil)
defaults.set([], forKey: SharedKeys.spokenLanguages)
engine.setSelectedLanguage("en")
settle(engine)
precondition(engine.enabledDictionaryLanguages == ["en"], "Removed dictionaries survived preference changes")

defaults.set(["en"], forKey: SharedKeys.spokenLanguages)
engine.setSelectedLanguage("fr")
settle(engine)
let reused = acceptanceIDs(engine)
let began = CFAbsoluteTimeGetCurrent()
for _ in 0..<100 {
    engine.setSelectedLanguage("fr")
    engine.setLanguage(forRecentText: "Je vais envoyer la facture and the updated invoice demain matin")
    precondition(engine.spellCheck("the", previousWord: "la") == nil)
    precondition(engine.spellCheck("bonjour", previousWord: "the") == nil)
}
let lookupMS = (CFAbsoluteTimeGetCurrent() - began) * 1000
precondition(acceptanceIDs(engine) == reused, "Repeated contexts churned dictionary mappings")
for _ in 0..<20 {
    engine.setSelectedLanguage("en")
    engine.setSelectedLanguage("fr")
}
settle(engine)
let native = Mirror(reflecting: engine).children.first { $0.label == "aospTrieEngine" }!.value as! AOSPTrieEngine
precondition(native.mountedLanguage == "fr", "An older load marked the wrong correction language ready")
precondition(engine.spellCheck("bonjor")?.correction == "bonjour")
print("PASS: exact bilingual words, contextual protection, selected-language mixed fallback, scoped additions/removal and map reuse")
print("PASS: rapid language replacement finishes with the latest correction dictionary")
print("MEASURE: 100 mixed-context/lookup batches = \(lookupMS)ms on simulator; no phone-latency claim")
"""#.replacingOccurrences(of: "KEYBOARD_BUNDLE", with: keyboard)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-multilingual-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("check")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Failed: \(args.first ?? "command")")
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["swiftc", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-I", products,
             "-I", derived + "/Build/Intermediates.noindex/Dictus.build/Debug-iphonesimulator/DictusKeyboard.build/Objects-normal/arm64",
             "-I", "DictusKeyboard/Vendored/AOSPTrie/bridge", source.path,
             keyboard + "/DictusKeyboard.debug.dylib", "-Xlinker", "-rpath", "-Xlinker", keyboard, "-o", binary.path])
_ = try run(["simctl", "spawn", simulator, binary.path])
