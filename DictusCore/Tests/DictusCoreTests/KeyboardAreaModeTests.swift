// DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift
// Contract tests for the single keyboard-area mode value (#271).
import XCTest
@testable import DictusCore

final class KeyboardAreaModeTests: XCTestCase {
    func testFullAreaModesOwnTheirOverlaySurface() {
        XCTAssertTrue(KeyboardAreaMode.keys.usesVoiceActionControls)
        XCTAssertTrue(KeyboardAreaMode.recording.usesVoiceActionControls)
        XCTAssertFalse(KeyboardAreaMode.letters.usesVoiceActionControls)
        XCTAssertFalse(KeyboardAreaMode.emoji.usesVoiceActionControls)
        XCTAssertFalse(KeyboardAreaMode.panel.usesVoiceActionControls)
    }

    // MARK: - Cases

    func testEnumHasOnlyVoiceModes() {
        XCTAssertEqual(KeyboardAreaMode.allCases, [.keys, .letters, .emoji, .panel, .recording])
    }

    func testRawValues() {
        XCTAssertEqual(KeyboardAreaMode.keys.rawValue, "keys")
        XCTAssertEqual(KeyboardAreaMode.recording.rawValue, "recording")
    }

    // MARK: - Which statuses own the keyboard area

    func testInFlightStatusesOwnTheKeyboardArea() {
        XCTAssertTrue(DictationStatus.requested.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.recording.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.transcribing.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.processing.ownsKeyboardArea)
    }

    func testTerminalStatusesDoNotOwnTheKeyboardArea() {
        XCTAssertFalse(DictationStatus.idle.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.ready.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.failed.ownsKeyboardArea)
    }

    // MARK: - Transitions

    func testDictationTakesOverFromEveryMode() {
        for mode in KeyboardAreaMode.allCases {
            XCTAssertEqual(
                KeyboardAreaMode.resolving(status: .requested, current: mode),
                .recording,
                "a requested dictation must take the area from \(mode.rawValue)"
            )
        }
    }

    func testEndingADictationReturnsToTheKeyGrid() {
        for status in [DictationStatus.idle, .ready, .failed] {
            XCTAssertEqual(
                KeyboardAreaMode.resolving(status: status, current: .recording),
                .keys,
                "leaving a dictation via \(status.rawValue) must restore the key grid"
            )
        }
    }

    func testAnIdleStatusReturnsToKeys() {
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .idle, current: .keys), .keys)
    }

    func testResolvingIsIdempotent() {
        for status in DictationStatus.allCases {
            for mode in KeyboardAreaMode.allCases {
                let once = KeyboardAreaMode.resolving(status: status, current: mode)
                let twice = KeyboardAreaMode.resolving(status: status, current: once)
                XCTAssertEqual(once, twice, "status=\(status.rawValue) mode=\(mode.rawValue)")
            }
        }
    }

    func testRecordingOwnsAreaAndPreventsPanelSwitches() {
        XCTAssertEqual(
            KeyboardAreaMode.resolving(status: .recording, current: .panel),
            .recording
        )
        XCTAssertEqual(
            KeyboardAreaMode.resolving(status: .ready, current: .recording),
            .keys
        )
    }

    func testTranscriptionAndCleanupLeaveAuxiliaryPagesReachable() {
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .transcribing, current: .recording), .keys)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .processing, current: .recording), .keys)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .transcribing, current: .emoji), .emoji)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .processing, current: .panel), .panel)
    }

    func testClosingAnAuxiliaryAreaLeavesKeysAvailable() {
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .ready, current: .emoji), .emoji)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .ready, current: .panel), .panel)
        XCTAssertEqual(KeyboardAreaMode.resolving(status: .ready, current: .recording), .keys)
    }

    func testSymbolsActionTogglesBetweenPanelAndKeys() {
        XCTAssertEqual(KeyboardAreaMode.toggledPanel(from: .keys), .panel)
        XCTAssertEqual(KeyboardAreaMode.toggledPanel(from: .panel), .keys)
    }

    func testSymbolsPageHasAnExplicitReturnToABCTransition() {
        // The symbols page must expose the inverse transition so its ABC
        // control can return to the normal key page without relying on UI state.
        XCTAssertEqual(KeyboardAreaMode.toggledPanel(from: .panel), .keys)
        XCTAssertNotEqual(KeyboardAreaMode.toggledPanel(from: .panel), .panel)
    }

    func testPanelRouteClosesToKeysAndRestores123Title() {
        let panel = KeyboardAreaMode.toggledPanel(from: .keys)
        XCTAssertEqual(panel, .panel)
        XCTAssertEqual(panel.modeControlTitle, "ABC")
        let keys = KeyboardAreaMode.toggledPanel(from: panel)
        XCTAssertEqual(keys, .keys)
        XCTAssertEqual(keys.modeControlTitle, "123")
    }

    func testModeControlTitleReflectsTheVisibleSurface() {
        XCTAssertEqual(KeyboardAreaMode.keys.modeControlTitle, "123")
        XCTAssertEqual(KeyboardAreaMode.letters.modeControlTitle, "123")
        XCTAssertEqual(KeyboardAreaMode.recording.modeControlTitle, "123")
        XCTAssertEqual(KeyboardAreaMode.emoji.modeControlTitle, "ABC")
        XCTAssertEqual(KeyboardAreaMode.panel.modeControlTitle, "ABC")
    }
}
