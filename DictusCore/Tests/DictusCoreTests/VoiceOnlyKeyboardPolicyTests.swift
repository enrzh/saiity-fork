import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardPolicyTests: XCTestCase {
    func testRightRailFitsWithinVoiceSurfaceHeight() {
        XCTAssertLessThanOrEqual(
            VoiceOnlyKeyboardPolicy.rightRailHeight,
            VoiceOnlyKeyboardPolicy.surfaceHeight
        )
    }

    func testRightRailUsesThreeCommandsAndOneSeparateDismissAction() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailControlCount, 3)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.commandClusterSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailHeight, 88)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)
        XCTAssertEqual(layout.rightRailTop, 8)
        XCTAssertEqual(layout.rightRailBottom, 96)
        XCTAssertEqual(layout.dismissTop, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize)
        XCTAssertEqual(layout.dismissBottom, VoiceOnlyKeyboardPolicy.surfaceHeight)
        XCTAssertEqual(layout.dismissBottom - layout.dismissTop, 44)
        XCTAssertGreaterThanOrEqual(layout.dismissTop, layout.rightRailBottom)
    }

    func testVoiceSurfaceUsesAvailableWidthAndCentersMicBetweenEqualRails() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)

        XCTAssertEqual(layout.surfaceWidth, 430)
        XCTAssertEqual(layout.leftRailWidth, 176)
        XCTAssertEqual(layout.rightRailWidth, 88)
        XCTAssertEqual(layout.centerX, 259)
    }

    func testVoiceOnlySurfaceDoesNotUseLegacyKeyGrid() {
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.usesLegacyKeyGrid)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.contentHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
    }

    func testAlternateContentUsesTheFullFixedSurfaceForFourUsableRows() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.contentHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
        let contentTop = (VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.contentHeight) / 2
        XCTAssertEqual(contentTop, 0)
        XCTAssertEqual(contentTop + VoiceOnlyKeyboardPolicy.contentHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.contentHeight / 4, 44)
    }

    func testBottomUtilitiesShareOneHorizontalRail() {
        for width in [320.0, 375, 390, 430] {
            let frames = VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: width)
            let bottomY = VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize
            XCTAssertEqual(frames.at.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.emoji.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.number.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.next.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.at.minX, 10, "width=\(width)")
            XCTAssertEqual(frames.emoji.minX, 54, "width=\(width)")
            XCTAssertEqual(frames.number.minX, 98, "width=\(width)")
            XCTAssertEqual(frames.next.minX, 142, "width=\(width)")
            XCTAssertEqual(Set([frames.at, frames.emoji, frames.number, frames.next]).count, 4)
        }
    }

    func testLanguageIndicatorSeparatesReadableVisualWidthFromHitHeight() {
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.languageVisualWidth, 56)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.languageVisualWidth, 60)
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
    }

    func testVoiceOnlyRailUsesAppleKeyboardVerticalInsets() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.verticalPadding, 8)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailVerticalPadding, 8)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailHeight, 88)
    }

    func testVoiceOnlySurfaceUsesReferenceHorizontalInsetAndControlGeometry() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.horizontalPadding, 10)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.primaryControlSize, 54)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.railSpacing, 0)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
        XCTAssertLessThanOrEqual(
            VoiceOnlyKeyboardPolicy.layout(for: 390).rightRailBottom,
            VoiceOnlyKeyboardPolicy.layout(for: 390).dismissTop
        )
    }

    func testPrimaryMicrophoneIsAStableAccessibleControl() {
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.primaryControlSize, 52)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.primaryControlSize, 56)
    }

    func testPrimaryControlUsesWideCapsuleWithinNarrowCenterArea() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.primaryControlWidth(availableWidth: 430, centerAreaWidth: 322), 167.7, accuracy: 0.01)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.primaryControlWidth(availableWidth: 320, centerAreaWidth: 212), 132)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.primaryControlWidth(availableWidth: 375, centerAreaWidth: 267), 146.25, accuracy: 0.01)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.layout(for: 140).leftRailWidth, 0)
    }

    func testVoiceSurfaceCentersMicWithinAreaBetweenRails() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)

        XCTAssertEqual(layout.centerX, 259)
        let expectedCenterX = 10.0 + 176.0 + (430.0 - 10.0 - 176.0 - 88.0 - 10.0) / 2.0
        XCTAssertEqual(layout.centerX, expectedCenterX)
    }

    func testVoiceSurfaceKeepsFullRailsCenteredAcrossTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)

            XCTAssertEqual(layout.horizontalInset, 10, "width=\(width)")
            let hasRails = width >= 360
            XCTAssertEqual(layout.leftRailWidth, hasRails ? 176 : 0, "width=\(width)")
            XCTAssertEqual(layout.rightRailWidth, hasRails ? 88 : 0, "width=\(width)")
            XCTAssertEqual(layout.centerX, hasRails ? width / 2 + 44 : width / 2, "width=\(width)")
            XCTAssertLessThanOrEqual(
                layout.horizontalInset * 2 + layout.leftRailWidth
                    + layout.centerAreaWidth + layout.rightRailWidth,
                width,
                "width=\(width)"
            )
        }
    }

    func testVoiceSurfaceCapsInsetAtHalfOfExtremelyNarrowWidth() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 12)

        XCTAssertEqual(layout.horizontalInset, 6)
        XCTAssertEqual(layout.leftRailWidth, 0)
        XCTAssertEqual(layout.rightRailWidth, 0)
        XCTAssertEqual(layout.centerAreaWidth, 0)
        XCTAssertEqual(layout.centerX, 6)
        XCTAssertLessThanOrEqual(
            layout.horizontalInset * 2 + layout.leftRailWidth
                + layout.centerAreaWidth + layout.rightRailWidth,
            12
        )
    }

    func testVoiceSurfaceExposesStableCenterAreaAndRailGeometry() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)

        XCTAssertEqual(layout.leftRailWidth, 176)
        XCTAssertEqual(layout.rightRailWidth, 88)
        XCTAssertEqual(layout.centerAreaWidth, 106)
        XCTAssertEqual(layout.centerX, 239)
        XCTAssertEqual(layout.rightRailHeight, 88)
    }

    func testNormalPhoneWidthsKeepFourUtilityTargetsOutsideCenterSurface() {
        for width in [375.0, 390, 420] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)

            XCTAssertEqual(layout.leftRailWidth, 176, "width=\(width)")
            XCTAssertEqual(layout.rightRailWidth, 88, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.next.maxX, 186, "width=\(width)")
            XCTAssertEqual(layout.micCenterArea.minX, 186, "width=\(width)")
            XCTAssertEqual(layout.micCenterArea.maxX, width - 98, "width=\(width)")
            XCTAssertFalse(layout.micCenterArea.intersects(layout.leftUtilityFrames.next), "width=\(width)")
            XCTAssertFalse(layout.micCenterArea.intersects(layout.rightCommandFrame), "width=\(width)")
        }
    }

    func testLayoutUsesTheRuntimeSurfaceHeightForBottomActions() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 216)

        XCTAssertEqual(layout.contentHeight, 216)
        XCTAssertEqual(layout.leftUtilityFrames.number.minY, 172)
        XCTAssertEqual(layout.dismissFrame, CGRect(x: 292, y: 172, width: 88, height: 44))
        XCTAssertLessThanOrEqual(layout.rightRailBottom, layout.dismissFrame.minY)
        XCTAssertTrue(layout.actionRectangles.allSatisfy { $0.maxY <= 216 })
    }

    func testCompactGeometryKeepsGlobalCenterAndAvoidsNarrowOverlap() {
        for width in [375.0, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            XCTAssertEqual(layout.centerX, width >= 360 ? width / 2 + 44 : width / 2)
        }
        let narrow = VoiceOnlyKeyboardPolicy.layout(for: 320)
        let capsule = VoiceOnlyKeyboardPolicy.primaryControlWidth(
            availableWidth: 320,
            centerAreaWidth: narrow.centerAreaWidth
        )
        XCTAssertLessThanOrEqual(160 + capsule / 2, 320 - 10 - 44)
        XCTAssertGreaterThanOrEqual(160 - capsule / 2, 10 + 44 - 132)
    }

    func testCommandClusterCellsKeep44PointTargetsAndFitVerticalBounds() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 375)
        XCTAssertEqual(layout.rightRailBottom - layout.rightRailTop, 88)
        XCTAssertLessThanOrEqual(layout.rightRailBottom, VoiceOnlyKeyboardPolicy.surfaceHeight)
    }

    func testRightRailGroupsFitWithoutOverlapAtTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)

            XCTAssertGreaterThanOrEqual(layout.rightRailTop, 0, "width=\(width)")
            XCTAssertLessThanOrEqual(layout.rightRailBottom, VoiceOnlyKeyboardPolicy.surfaceHeight, "width=\(width)")
            XCTAssertGreaterThanOrEqual(layout.dismissTop, layout.rightRailBottom, "hit ranges must not overlap, width=\(width)")
            XCTAssertLessThanOrEqual(layout.dismissBottom, VoiceOnlyKeyboardPolicy.surfaceHeight, "width=\(width)")
            XCTAssertEqual(layout.dismissBottom - layout.dismissTop, VoiceOnlyKeyboardPolicy.controlSize, "width=\(width)")
            XCTAssertTrue(layout.rightRailWidth == 0 || layout.rightRailWidth >= VoiceOnlyKeyboardPolicy.controlSize, "width=\(width)")
            XCTAssertGreaterThanOrEqual(layout.centerAreaWidth, 0, "width=\(width)")
        }
    }

    func testBottomGlyphsKeep44PointTargetsWithoutVisualContainers() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
    }

    func testVoiceSurfaceShrinksRailsWhenWidthCannotFitFullControls() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 80)

        XCTAssertEqual(layout.centerAreaWidth, 60)
        XCTAssertEqual(layout.leftRailWidth, 0)
        XCTAssertEqual(layout.rightRailWidth, 0)
        XCTAssertEqual(layout.horizontalInset, 10)
        XCTAssertEqual(layout.centerX, 40)
        XCTAssertLessThanOrEqual(
            layout.leftRailWidth + layout.rightRailWidth
                + layout.horizontalInset * 2,
            layout.surfaceWidth
        )
    }

    func testVoiceSurfaceHidesLanguageIndicatorWhenLeftRailCannotFitIt() {
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.layout(for: 80).showsLanguageIndicator)
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.layout(for: 12).showsLanguageIndicator)
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.layout(for: 320).showsLanguageIndicator)
    }

    func testVoiceOnlyActionMappingUsesExistingCommands() {
        XCTAssertEqual(KeyboardCommand.delete.proxyAction, .deleteBackward)
        XCTAssertEqual(KeyboardCommand.returnKey.proxyAction, .insertText("\n"))
        XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
    }

    func testDeleteAndReturnUseExactEightyEightByFortyFourFrames() {
        let frames = VoiceOnlyKeyboardPolicy.rightRailFrames(for: 390)

        XCTAssertEqual(frames.delete.size, CGSize(width: 88, height: 44))
        XCTAssertEqual(frames.returnKey.size, CGSize(width: 88, height: 44))
        XCTAssertFalse(frames.delete.intersects(frames.returnKey))
    }

    func testRightRailFitsAtSupportedWidthsAndLeavesMicCenterAvailable() {
        for width in [320.0, 375, 390, 430] {
            let frames = VoiceOnlyKeyboardPolicy.rightRailFrames(for: width)
            XCTAssertGreaterThanOrEqual(frames.delete.minX, 0, "width=\(width)")
            XCTAssertLessThanOrEqual(frames.delete.maxX, width, "width=\(width)")
            XCTAssertGreaterThanOrEqual(frames.delete.minY, 0, "width=\(width)")
            XCTAssertLessThanOrEqual(frames.returnKey.maxY, VoiceOnlyKeyboardPolicy.surfaceHeight, "width=\(width)")
            XCTAssertFalse(frames.delete.intersects(frames.returnKey), "width=\(width)")
        }
    }

    func testTaskTwoSurfaceAndBottomActionContractsRemainStable() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.bottomActionHitHeight, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.actionHitSize, CGSize(width: 88, height: 44))
        XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
    }

    func testActionCentersAndRectanglesFitWithoutOverlapAtTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            let rectangles = layout.actionRectangles

            XCTAssertEqual(rectangles.count, width >= 360 ? 8 : 1, "width=\(width)")
            XCTAssertTrue(rectangles.allSatisfy { $0.minX >= 0 && $0.maxX <= width && $0.minY >= 0 && $0.maxY <= VoiceOnlyKeyboardPolicy.surfaceHeight }, "width=\(width)")
            for (index, rectangle) in rectangles.enumerated() {
                XCTAssertEqual(rectangle.width, 44, accuracy: 0.001, "index=\(index), width=\(width)")
                XCTAssertEqual(rectangle.height, 44, accuracy: 0.001, "index=\(index), width=\(width)")
                for other in rectangles[(index + 1)...] {
                    XCTAssertFalse(rectangle.intersects(other), "index=\(index), width=\(width)")
                }
            }
            XCTAssertFalse(layout.micCenterArea.intersects(layout.rightCommandFrame))
            XCTAssertEqual(layout.leftBottomCenterX, 10)
            XCTAssertEqual(layout.rightBottomCenterX, width >= 360 ? width - 54 : width - 32)
        }
    }

    func testUIKitUtilityFramesFitWithoutOverlapAtTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let left = VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: width)
            let right = VoiceOnlyKeyboardPolicy.rightRailFrames(for: width)
            let frames = [left.at, left.emoji, left.number, left.next,
                          right.delete, right.returnKey,
                          VoiceOnlyKeyboardPolicy.dismissFrame(for: width)]

            XCTAssertTrue(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width && $0.minY >= 0 && $0.maxY <= VoiceOnlyKeyboardPolicy.surfaceHeight }, "width=\(width)")
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    XCTAssertFalse(frame.intersects(other), "index=\(index), width=\(width)")
                }
            }
            XCTAssertEqual(right.delete.size, VoiceOnlyKeyboardPolicy.actionHitSize)
            XCTAssertEqual(right.returnKey.size, VoiceOnlyKeyboardPolicy.actionHitSize)
        }
    }

    func testProxyCommandsRouteOnceAndRespectDisabledState() {
        var deletes = 0
        var inserts: [String] = []

        KeyboardCommand.delete.perform(deleteBackward: { deletes += 1 }, insertText: { inserts.append($0) })
        KeyboardCommand.returnKey.perform(deleteBackward: { deletes += 1 }, insertText: { inserts.append($0) })
        KeyboardCommand.at.perform(deleteBackward: { deletes += 1 }, insertText: { inserts.append($0) })
        KeyboardCommand.delete.perform(ifEnabled: false, deleteBackward: { deletes += 1 }, insertText: { inserts.append($0) })

        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(inserts, ["\n", "@"])
    }

    func testVoiceVisualAndUIKitRectsShareAbsoluteSurfaceGeometry() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            let left = VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: width)
            let right = VoiceOnlyKeyboardPolicy.rightRailFrames(for: width)

            XCTAssertEqual(layout.languageFrame.minX, layout.horizontalInset, "width=\(width)")
            XCTAssertEqual(layout.languageFrame.minY, VoiceOnlyKeyboardPolicy.topInset, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.at, left.at, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.emoji, left.emoji, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.number, left.number, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.next, left.next, "width=\(width)")
            XCTAssertEqual(layout.deleteFrame, right.delete, "width=\(width)")
            XCTAssertEqual(layout.returnFrame, right.returnKey, "width=\(width)")
            XCTAssertEqual(layout.dismissFrame, VoiceOnlyKeyboardPolicy.dismissFrame(for: width), "width=\(width)")
            XCTAssertTrue(layout.micCenterArea.contains(CGPoint(x: layout.centerX, y: layout.micCenterArea.midY)))
            if layout.leftRailWidth > 0 {
                XCTAssertFalse(layout.micCenterArea.intersects(layout.leftUtilityFrames.at))
            }
            XCTAssertFalse(layout.micCenterArea.intersects(layout.rightCommandFrame))
        }
    }

    func testRailsHaveTopInsetAndDismissIsCompleteAtBottom() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)

        XCTAssertEqual(VoiceOnlyKeyboardPolicy.topInset, 8)
        XCTAssertEqual(layout.deleteFrame.size, CGSize(width: 88, height: 44))
        XCTAssertEqual(layout.returnFrame.size, CGSize(width: 88, height: 44))
        XCTAssertEqual(layout.deleteFrame.minY, 8)
        XCTAssertEqual(layout.dismissFrame.maxY, VoiceOnlyKeyboardPolicy.surfaceHeight)
        XCTAssertEqual(layout.dismissFrame.minY, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize)
        XCTAssertEqual(layout.leftUtilityFrames.number.minY, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize)
        XCTAssertEqual(layout.leftUtilityFrames.next.minY, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize)
    }

    func testNextKeyboardVisualIsSmallButItsHitRectIsFortyFourPoints() {
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.nextKeyboardVisualSize, 16)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.nextKeyboardVisualSize, 20)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: 390).next.size,
                       CGSize(width: 44, height: 44))
    }

    func testActionVisualsUseThirtySixPointVisualsInsideEightyEightByFortyFourContainers() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.actionHitSize, CGSize(width: 88, height: 44))
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, VoiceOnlyKeyboardPolicy.actionHitSize.height)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, VoiceOnlyKeyboardPolicy.surfaceHeight)
    }

    func testKeyboardHeightUsesNativeProviderContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controller.contains("let deviceContext = DeviceContext.current"))
        XCTAssertTrue(controller.contains("KeyboardHeightProvider.height("))
        XCTAssertTrue(controller.contains("traitCollection: traitCollection"))
    }
}
