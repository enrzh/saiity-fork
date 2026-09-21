import XCTest
@testable import DictusCore

final class KeyboardAccessoryOrderPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = AppGroup.defaults
        defaults.removeObject(forKey: SharedKeys.keyboardAccessoryOrder)
    }

    override func tearDown() {
        defaults.removeObject(forKey: SharedKeys.keyboardAccessoryOrder)
        defaults = nil
        super.tearDown()
    }

    func testMissingAndInvalidValuesUseTheFixedNativeOrder() {
        XCTAssertEqual(KeyboardAccessoryOrder.load(from: defaults), .numberFirst)

        defaults.set("unsupported", forKey: SharedKeys.keyboardAccessoryOrder)

        XCTAssertEqual(KeyboardAccessoryOrder.load(from: defaults), .numberFirst)
    }

    func testLegacyOrderPersistenceCannotChangeTheRenderedOrder() {
        for order in KeyboardAccessoryOrder.allCases {
            order.persist(to: defaults)

            XCTAssertEqual(defaults.string(forKey: SharedKeys.keyboardAccessoryOrder), order.rawValue)
            XCTAssertEqual(KeyboardAccessoryOrder.load(from: defaults), .numberFirst)
        }
    }

    func testOrderTitlesDescribeTheRenderedBottomControls() {
        XCTAssertEqual(KeyboardAccessoryOrder.emojiFirst.displayName, "Emoji, 123")
        XCTAssertEqual(KeyboardAccessoryOrder.numberFirst.displayName, "123, Emoji")
    }

    func testCurrentAlwaysUsesTheNativeNumberFirstOrder() {
        XCTAssertEqual(KeyboardAccessoryOrder.current, .numberFirst)

        defaults.set(KeyboardAccessoryOrder.numberFirst.rawValue,
                     forKey: SharedKeys.keyboardAccessoryOrder)

        XCTAssertEqual(KeyboardAccessoryOrder.load(from: defaults), .numberFirst)
    }

    func testAuxiliaryBottomBarConsumesTheSharedControlOrder() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bar = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/Views/AuxiliaryBottomBar.swift"),
            encoding: .utf8
        )
        let root = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"),
            encoding: .utf8
        )
        let picker = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/Views/EmojiPickerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(bar.contains("let layout: VoiceOnlyKeyboardPolicy.Layout"))
        XCTAssertTrue(bar.contains("chromeNumbersFrame"))
        XCTAssertTrue(bar.contains("chromeLettersFrame"))
        XCTAssertFalse(bar.contains("chromeWideLettersFrame"))
        XCTAssertFalse(bar.contains("layout.auxiliaryMicrophoneFrame"))
        XCTAssertTrue(picker.contains("VoiceOnlyKeyboardPolicy.keyGridInset"))
        XCTAssertFalse(picker.contains("surfaceLayout.auxiliaryControlFrames.first"))
        XCTAssertTrue(root.contains("controlOrder: KeyboardAccessoryOrder.current"))
    }

    func testOrderAwareLayoutKeepsBottomControlFramesDeterministic() {
        let emojiFirst = VoiceOnlyKeyboardPolicy.layout(
            for: 390,
            surfaceHeight: 216,
            controlOrder: .emojiFirst
        )
        let numberFirst = VoiceOnlyKeyboardPolicy.layout(
            for: 390,
            surfaceHeight: 216,
            controlOrder: .numberFirst
        )

        XCTAssertEqual(
            emojiFirst.auxiliaryControlFrames,
            [emojiFirst.leftUtilityFrames.emoji, emojiFirst.leftUtilityFrames.number]
        )
        XCTAssertEqual(
            numberFirst.auxiliaryControlFrames,
            [numberFirst.leftUtilityFrames.number, numberFirst.leftUtilityFrames.emoji]
        )
        XCTAssertEqual(emojiFirst.leftUtilityFrames.emoji.minX,
                       numberFirst.leftUtilityFrames.number.minX)
        XCTAssertEqual(emojiFirst.leftUtilityFrames.number.minX,
                       numberFirst.leftUtilityFrames.emoji.minX)
        XCTAssertEqual(emojiFirst.leftUtilityFrames.emoji.minY,
                       numberFirst.leftUtilityFrames.number.minY)
        XCTAssertEqual(emojiFirst.leftUtilityFrames.number.minY,
                       numberFirst.leftUtilityFrames.emoji.minY)
    }

    func testAuxiliaryContentAndControlsShareTheInsetSurfaceAndBottomLane() {
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: 390,
            surfaceHeight: 216,
            controlOrder: .emojiFirst
        )
        let surface = layout.surfaceFrame
        let content = layout.auxiliaryContentFrame
        let controls = layout.bottomAuxiliaryControlFrame

        XCTAssertEqual(surface, CGRect(x: 0, y: 4, width: 390, height: 208))
        XCTAssertTrue(surface.contains(content))
        XCTAssertTrue(surface.contains(controls))
        XCTAssertEqual(content.minX, surface.minX)
        XCTAssertEqual(content.width, surface.width)
        XCTAssertEqual(controls.minX, surface.minX)
        XCTAssertEqual(controls.width, surface.width)
        XCTAssertEqual(controls.maxY, surface.maxY - VoiceOnlyKeyboardPolicy.chromeBottomInset)
        XCTAssertEqual(content.maxY, controls.minY - VoiceOnlyKeyboardPolicy.visibleControlGap)
    }

    func testAuxiliaryMicrophoneKeepsItsPhysicalSlotAcrossPagesAndAccessoryOrders() {
        for order in KeyboardAccessoryOrder.allCases {
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: 390,
                surfaceHeight: 216,
                controlOrder: order
            )

            XCTAssertEqual(layout.auxiliaryMicrophoneFrame, layout.leftUtilityFrames.number)
            XCTAssertTrue(layout.bottomAuxiliaryControlFrame.contains(layout.auxiliaryMicrophoneFrame))
        }
    }

    func testKeyboardInputViewInitializersKeepTheOuterViewTransparent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/InputView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("backgroundColor = .clear"))
        XCTAssertTrue(source.contains("isOpaque = false"))
        XCTAssertFalse(source.contains("systemGroupedBackground"))
    }
}
