import XCTest
@testable import DictusCore

final class EmojiSkinToneVariantsTests: XCTestCase {
    func testThumbsUpOffersDefaultAndFiveSkinTones() {
        let options = EmojiSkinToneVariants.options(for: "👍")
        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options.first, "👍")
        XCTAssertEqual(options[1], "👍🏻")
        XCTAssertEqual(options[5], "👍🏿")
    }

    func testSmileysWithoutSkinSupportHaveNoPopup() {
        XCTAssertEqual(EmojiSkinToneVariants.options(for: "😀"), [])
        XCTAssertEqual(EmojiSkinToneVariants.options(for: "❤️"), [])
        XCTAssertEqual(EmojiSkinToneVariants.options(for: "🇫🇷"), [])
    }

    func testAlreadyTonedEmojiStillOffersTheFullScale() {
        let options = EmojiSkinToneVariants.options(for: "👍🏽")
        XCTAssertEqual(options.first, "👍")
        XCTAssertEqual(options.count, 6)
        XCTAssertTrue(options.contains("👍🏽"))
    }

    func testVictoryHandDropsTheVariationSelectorWhenToning() {
        let options = EmojiSkinToneVariants.options(for: "✌️")
        XCTAssertEqual(options.count, 6)
        XCTAssertTrue(options.contains { option in
            option.unicodeScalars.contains { $0.value == 0x1F3FD }
        })
    }
}
