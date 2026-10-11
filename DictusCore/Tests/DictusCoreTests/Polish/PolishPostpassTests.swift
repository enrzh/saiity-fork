// DictusCore/Tests/DictusCoreTests/Polish/PolishPostpassTests.swift
import XCTest
@testable import DictusCore

final class PolishPostpassTests: XCTestCase {
    func testUnknownOrUnhandledLanguagesNeverUseEnglishLexicalRules() {
        for (raw, expected) in [
            ("a escola", "A escola"),
            ("a escola fica perto de casa e um amigo vem comigo", "A escola fica perto de casa e um amigo vem comigo"),
            ("hum a escola", "Hum a escola"),
            ("um amigo e uma amiga", "Um amigo e uma amiga"),
            ("ええ、明日の予定を確認します", "ええ、明日の予定を確認します"),
            ("אה אנחנו צריכים לבדוק את החשבונית", "אה אנחנו צריכים לבדוק את החשבונית")
        ] {
            XCTAssertEqual(PolishPostpass.cleanupFloor(raw, language: nil), expected, raw)
        }
        XCTAssertEqual(PolishPostpass.cleanupFloor("a escola", language: .portuguese), "A escola")
        XCTAssertEqual(PolishPostpass.cleanupFloor("uh I have a appointment at 2pm, actually 4pm", language: .english),
                       "I have an appointment at 4pm")
        XCTAssertEqual(PolishPostpass.cleanupFloor("go go now", language: .english), "Go go now")
    }

    func testUnknownCleanupKeepsBracketedTechnicalIdentifiers() {
        let text = "[API_240] [HTTP] [USD] Cafe\u{301}"
        XCTAssertEqual(PolishPostpass.cleanupFloor(text, language: nil), text)
        XCTAssertEqual(PolishPostpass.cleanupFloor("[BLANK_AUDIO] [APPLAUSE] " + text, language: nil), text)
    }

    func testUnhandledLanguageKeepsEnglishCorrectionWordsAndRepetitions() {
        for text in ["John, actually Jean", "el el texto", "well, a escola", "um amigo e uma amiga", "a palavra comma aparece no código"] {
            let expected = String(text.prefix(1)).uppercased() + text.dropFirst()
            XCTAssertEqual(PolishPostpass.cleanupFloor(text, language: .portuguese), expected, text)
        }
        XCTAssertEqual(PolishPostpass.cleanupFloor("John, actually Jean", language: .english), "Jean")
        XCTAssertEqual(PolishPostpass.cleanupFloor("euh je je sais que que c'est important", language: .french),
                       "Je sais que c'est important")
        XCTAssertEqual(VerbalPunctuationPrepass.apply("a palavra comma aparece no código", language: .portuguese),
                       "a palavra comma aparece no código")
    }


    // MARK: - Encode

    func testEncodeReplacesNewlinesWithMarker() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("a\nb\nc"),
            "a<<NL>>b<<NL>>c"
        )
    }

    func testEncodePreservesTextWithoutNewlines() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("hello world"),
            "hello world"
        )
    }

    func testEncodePreservesAdjacentMarkers() {
        XCTAssertEqual(
            PolishPostpass.encodeForEngine("\n\n"),
            "<<NL>><<NL>>"
        )
    }

    // MARK: - Decode: marker round-trip

    func testDecodeRestoresNewlinesFromMarker() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a<<NL>>b<<NL>>c", language: .french),
            "a\nb\nc"
        )
    }

    func testRoundTripPreservesMixedContent() {
        let original = "Bonjour,\nça va ?\nÀ bientôt."
        let encoded = PolishPostpass.encodeForEngine(original)
        // NBSP would be re-added on decode for `?` — bake the expected NBSP in.
        let expected = "Bonjour,\nça va\u{00A0}?\nÀ bientôt."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(encoded, language: .french),
            expected
        )
    }

    // MARK: - Decode: French NBSP

    func testDecodeInsertsNBSPBeforeFrenchQuestion() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Salut, comment ça va ?", language: .french),
            "Salut, comment ça va\u{00A0}?"
        )
    }

    func testDecodeInsertsNBSPBeforeAllFrenchDoubleMarks() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Hey ! Quoi ? Vraiment : oui ; non.", language: .french),
            "Hey\u{00A0}! Quoi\u{00A0}? Vraiment\u{00A0}: oui\u{00A0}; non."
        )
    }

    func testDecodeLeavesExistingNBSPUntouched() {
        let alreadyClean = "Salut\u{00A0}? J'ai bien lu."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(alreadyClean, language: .french),
            alreadyClean
        )
    }

    func testDecodeDoesNotTouchNonFrenchTypography() {
        let input = "Hi how are you ? Just asking ! Right ?"
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .english),
            input
        )
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .spanish),
            input
        )
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(input, language: .german),
            input
        )
    }

    func testDecodeDoesNotInsertNBSPWhenNoSpacePresent() {
        // No space between word and mark → leave alone (model already produced
        // tight punctuation, no French rule violation to repair).
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Salut?", language: .french),
            "Salut?"
        )
    }

    func testDecodeInsertsNBSPOnlyOnceForOneSpace() {
        // Defensive: pattern should not match `[ \t]` runs greedily and end up
        // inserting multiple NBSPs.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a ?", language: .french),
            "a\u{00A0}?"
        )
    }

    // MARK: - Decode: stray-newline collapse (fix A)

    func testDecodeCollapsesStackedNewlines() {
        // Marker decodes to one `\n`; the model added 3 more around it.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a.<<NL>>\n\n\nb", language: .french),
            "a.\nb"
        )
    }

    func testDecodeCollapsesNewlinesWithSurroundingSpaces() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("réunion. \n\n\n\n Premièrement", language: .french),
            "réunion.\nPremièrement"
        )
    }

    func testDecodeLeavesSingleNewlineUntouched() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("a<<NL>>b", language: .french),
            "a\nb"
        )
    }

    func testDecodeTrickyMeetingRecapHasSingleBreaks() {
        // Test 4 from the 08/06 Wispr comparison: 3 line breaks, each previously
        // ballooned to `\n\n\n\n`. Expect exactly one `\n` per section.
        let engineOutput = "Voici le compte rendu.<<NL>>\n\n\nPremièrement, on a validé le budget\u{00A0}!<<NL>>\n\n\nDeuxièmement, d'accord\u{00A0}?<<NL>>\n\n\nA très vite."
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine(engineOutput, language: .french),
            "Voici le compte rendu.\nPremièrement, on a validé le budget\u{00A0}!\nDeuxièmement, d'accord\u{00A0}?\nÀ très vite."
        )
    }

    // MARK: - Decode: capital À accent (fix C)

    func testDecodeRestoresSentenceInitialAAfterNewline() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("Budget validé\u{00A0}!<<NL>>A très vite.", language: .french),
            "Budget validé\u{00A0}!\nÀ très vite."
        )
    }

    func testDecodeRestoresAAtStringStart() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A demain, on en reparle.", language: .french),
            "À demain, on en reparle."
        )
    }

    func testDecodeRestoresAAfterPeriod() {
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("C'est noté. A plus tard.", language: .french),
            "C'est noté. À plus tard."
        )
    }

    func testDecodeDoesNotTouchAFollowedByUppercase() {
        // "A" before an acronym / proper noun is left alone.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A WhisperKit on doit ça.", language: .french),
            "A WhisperKit on doit ça."
        )
    }

    func testDecodeDoesNotTouchAbbreviationA() {
        // "A." (abbreviation, no following space+lowercase) is left alone.
        XCTAssertEqual(
            PolishPostpass.decodeFromEngine("A. Dupont est là.", language: .french),
            "A. Dupont est là."
        )
    }

    func testDecodeAAccentIsFrenchOnly() {
        let input = "A demain."
        XCTAssertEqual(PolishPostpass.decodeFromEngine(input, language: .english), input)
        XCTAssertEqual(PolishPostpass.decodeFromEngine(input, language: .german), input)
    }

    // MARK: - Combined behaviour

    func testFullPipelineFrench() {
        // Simulate the full round-trip for the round-1 batch-1 event 2 case.
        let preprocessed = "Bonjour, comment ça va ?\nj'espère que tu vas bien,\nà bientôt."
        let engineInput = PolishPostpass.encodeForEngine(preprocessed)
        // Engine returns the same text with capitalisation (best-case model
        // behaviour) and a marker preserved.
        let engineOutput = "Bonjour, comment ça va ?<<NL>>J'espère que tu vas bien,<<NL>>À bientôt."
        let final = PolishPostpass.decodeFromEngine(engineOutput, language: .french)
        XCTAssertEqual(
            final,
            "Bonjour, comment ça va\u{00A0}?\nJ'espère que tu vas bien,\nÀ bientôt."
        )
        // Sanity: the encoding step turned every `\n` into the marker.
        XCTAssertFalse(engineInput.contains("\n"))
        XCTAssertTrue(engineInput.contains(PolishPostpass.newlineMarker))
    }

    func testCleanupFloorRemovesSafeFillersAndStuttersWithoutInventingSentenceMarks() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("uh i i think we should ship it"),
            "I think we should ship it"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("um we should ship it"),
            "We should ship it"
        )
    }

    func testCleanupFloorPreservesMeaningfulWordsAcrossLanguages() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("euh je je sais que que c'est important"),
            "Je sais que c'est important"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("啊我觉得这个方案很好"),
            "啊我觉得这个方案很好"
        )
    }

    func testCleanupFloorPreservesCJKAndMeaningfulWordsAcrossLanguages() {
        let input = "我觉得这个方案很好 er este very very"
        XCTAssertEqual(PolishPostpass.cleanupFloor(input), input)
    }

    func testCleanupFloorResolvesExplicitFalseStartsAndSelfCorrections() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("send it Tuesday, actually Wednesday"),
            "Send it Wednesday"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("envoie-le mardi, enfin mercredi"),
            "Envoie-le mercredi"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("schick es am Dienstag, eigentlich Mittwoch"),
            "Schick es am Mittwoch"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("envíalo martes, mejor miércoles"),
            "Envíalo miércoles"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("envíalo el martes, en realidad el miércoles"),
            "Envíalo el miércoles"
        )
    }

    func testCleanupFloorPreservesBoundaryNewlinesWhileCleaningOuterSpaces() {
        let input = "\n  very very important , actually this is the reason  \n"
        XCTAssertEqual(
            PolishPostpass.cleanupFloor(input),
            "\nVery very important, actually this is the reason\n"
        )
    }

    func testCleanupFloorNormalizesRealSpokenPunctuationAndCapitalization() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("uh send the report , tomorrow !"),
            "Send the report, tomorrow!"
        )
    }

    func testCleanupFloorKeepsMeaningfulRepetitionsAndCorrectionWords() {
        let input = "very very important, actually this is the reason"
        XCTAssertEqual(PolishPostpass.cleanupFloor(input), "Very very important, actually this is the reason")
    }

    func testCleanupFloorPreservesMarkdownAndNumberedListMarkers() {
        let input = "- first item\n  * nested item\n  2. another item"
        XCTAssertEqual(
            PolishPostpass.cleanupFloor(input, language: nil),
            "- First item\n  * Nested item\n  2. Another item"
        )
    }

    func testStructureGuardrailRejectsDroppedLinesAndListMarkers() {
        let raw = "- first\n- second"
        XCTAssertFalse(PolishGuardrail.preservesStructure(raw: raw, polished: "First and second", mode: .auto))
        XCTAssertTrue(PolishGuardrail.preservesStructure(raw: raw, polished: "- First\n- Second", mode: .auto))
        XCTAssertTrue(PolishGuardrail.preservesStructure(raw: raw, polished: "First and second", mode: .repair))
    }

    func testCleanupFloorAutoPathPreservesDistinctEventsAtTheSameTime() {
        let raw = "Hey Jack I got like a appointment at 2am, oh sorry, it's 4am Um, yeah. So basically I got a poem at 4 a. m. Can you come by please?"
        XCTAssertEqual(
            PolishPostpass.cleanupFloor(raw, language: nil),
            "Hey Jack I got an appointment at 4am. I got a poem at 4am. Can you come by please?"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor(raw, language: .english),
            "Hey Jack I got an appointment at 4am. I got a poem at 4am. Can you come by please?"
        )
    }

    func testGrammarFloorPreservesDistinctEventsWithoutCleanup() {
        let input = "I have a call at 2pm. I have a meeting at 2pm."
        XCTAssertEqual(TranscriptionPipeline.assemble(
            cleaned: input, grammarLanguage: nil, insertAsIs: true
        ).body, input)
    }

    func testCleanupFloorKeepsLikeWhenItIsAVerbOrComparison() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("I like a quiet office", language: nil),
            "I like a quiet office"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("it looks like a bug", language: nil),
            "It looks like a bug"
        )
    }

    func testCleanupFloorLanguageNeutralPreservesLanguageSpecificLexicalPatterns() {
        let inputs = [
            "el el texto",
            "de de tekst",
            "la la phrase",
            "y y seguimos",
            "allora ho parlato con Marco",
            "portanto vamos a continuar"
        ]

        for input in inputs {
            XCTAssertEqual(
                PolishPostpass.cleanupFloor(input, language: nil),
                input.prefix(1).uppercased() + input.dropFirst(),
                "language-neutral cleanup changed: \(input)"
            )
        }
    }

    func testCleanupFloorKnownLanguageStillRemovesLexicalStutters() {
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("el el texto", language: .spanish),
            "El texto"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("de de tekst", language: .german),
            "De tekst"
        )
    }

    func testNonSpeechEventLabelsAreStrippedIncludingTrailingFillers() {
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("hello (singing)~ there"),
            "hello there"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("a kiss [kiss]. later"),
            "a kiss later"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("quiet [BLANK_AUDIO] now"),
            "quiet now"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("intro ♪ verse"),
            "intro verse"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("Meet at (2024) campus"),
            "Meet at (2024) campus"
        )
        XCTAssertEqual(
            PolishPostpass.grammarFloor("uh hello (laughs) world", language: .english),
            "Hello world"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("(snow crunching) hello"),
            "hello"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("quiet (soft music) now"),
            "quiet now"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("aside (see attached) stays"),
            "aside (see attached) stays"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("credit (music director) stays"),
            "credit (music director) stays"
        )
        XCTAssertEqual(
            PolishPostpass.removeNonSpeechEventLabels("start *cough* end"),
            "start end"
        )
    }

    func testCleanupFloorStripsEnvironmentalNoiseAndGermanStallFrame() {
        let raw = "(snow crunching) So grundsätzlich habe ich jetzt einen Termin 15 Uhr. und heute dich dafür einladen."
        XCTAssertEqual(
            PolishPostpass.cleanupFloor(raw, language: nil),
            "So grundsätzlich habe ich jetzt einen Termin 15 Uhr. und heute dich dafür einladen."
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("Grundsätzlich stimme ich zu", language: nil),
            "Grundsätzlich stimme ich zu"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("So I have a meeting at 3", language: nil),
            "So I have a meeting at 3"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("Habe ich recht?", language: nil),
            "Habe ich recht?"
        )
        XCTAssertEqual(
            PolishPostpass.cleanupFloor("Ich habe einen Termin um 15 Uhr", language: nil),
            "Ich habe einen Termin um 15 Uhr"
        )
    }
}
