import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardPolicyTests: XCTestCase {
    func testSymbolGridMatchesAllSupportedWidthsAndThreeRealRows() {
        let rows: [[CGFloat]] = [
            Array(repeating: 1, count: 10),
            Array(repeating: 1, count: 10),
            [1.5, 0.5, 1.2, 1.2, 1.2, 1.2, 1.2, 0.5, 1.5]
        ]

        for width in [320, 375, 390, 430] {
            let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
                for: rows, in: CGSize(width: width, height: 184), spacing: 5, inset: 4
            )
            let bounds = CGRect(x: 0, y: 0, width: width, height: 184)

            XCTAssertEqual(frames.count, 3, "width=\(width)")
            XCTAssertEqual(frames.map(\.count), [10, 10, 9], "width=\(width)")
            XCTAssertEqual(frames.flatMap { $0 }.count, 29, "width=\(width)")
            XCTAssertTrue(frames.flatMap { $0 }.allSatisfy(bounds.contains), "width=\(width)")
            for row in frames {
                XCTAssertEqual(row.reduce(CGFloat.zero) { $0 + $1.width } + 5 * CGFloat(row.count - 1),
                               CGFloat(width - 8), accuracy: 0.001, "width=\(width)")
                for pair in zip(row, row.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.1.minX - pair.0.maxX, 5 - 0.001, "width=\(width)")
                    XCTAssertFalse(pair.0.intersects(pair.1), "width=\(width)")
                }
            }
        }
    }

    func testSymbolGridRecomputesRowHeightForDifferentContentHeights() {
        let rows = Array(repeating: [CGFloat](repeating: 1, count: 10), count: 3)
        let short = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: rows, in: CGSize(width: 390, height: 140), spacing: 5, inset: 4
        )
        let tall = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: rows, in: CGSize(width: 390, height: 184), spacing: 5, inset: 4
        )
        XCTAssertEqual(short[0][0].height, (140 - 10) / 3, accuracy: 0.001)
        XCTAssertEqual(tall[0][0].height, (184 - 10) / 3, accuracy: 0.001)
        XCTAssertGreaterThan(tall[0][0].height, short[0][0].height)
    }

    func testSymbolPageToggleContractRoutesBothTransitions() {
        XCTAssertEqual(
            VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(from: .symbols1),
            .symbols1ToSymbols2
        )
        XCTAssertEqual(
            VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(from: .symbols2),
            .symbols2ToClose
        )
    }

    func testSharedContractUsesSixByFourInsetsAndSplitsAlternatePageContent() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)

        XCTAssertEqual(VoiceOnlyKeyboardPolicy.horizontalPadding, 6)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.verticalPadding, 4)
        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.height, 44)
        XCTAssertEqual(layout.auxiliaryContentFrame.minY, layout.surfaceFrame.minY)
        XCTAssertEqual(layout.bottomAuxiliaryControlFrame,
                       CGRect(x: layout.surfaceFrame.minX,
                              y: layout.surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.visibleControlGap - VoiceOnlyKeyboardPolicy.controlSize,
                              width: layout.surfaceFrame.width,
                              height: VoiceOnlyKeyboardPolicy.controlSize))
        XCTAssertEqual(layout.auxiliaryContentFrame,
                       CGRect(x: layout.surfaceFrame.minX,
                              y: layout.surfaceFrame.minY,
                              width: layout.surfaceFrame.width,
                              height: layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap - layout.surfaceFrame.minY))
    }

    func testAuxiliaryAccessoryFramesAreCenteredAndNonOverlapping() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 228)
            let frames = layout.auxiliaryControlFrames

            XCTAssertEqual(Set(frames.map(\.minY)), Set([layout.bottomAuxiliaryControlFrame.minY]), "width=\(width)")
            XCTAssertTrue(frames.allSatisfy { $0.height >= 44 && layout.bottomAuxiliaryControlFrame.contains($0) },
                          "width=\(width), frames=\(frames)")
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    XCTAssertFalse(frame.intersects(other), "width=\(width)")
                }
            }
        }
    }

    func testAuxiliaryAccessoryFramesFailClosedBelow246PointSurfaceWidth() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 252, surfaceHeight: 216)
        XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy(\.isEmpty))
        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.minX, layout.surfaceFrame.minX)
        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.width, layout.surfaceFrame.width)
    }

    func testAuxiliaryAccessoryFramesFailClosedWhenRowCannotReach44Points() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 43)

        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.height, VoiceOnlyKeyboardPolicy.controlSize)
        XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy(\.isEmpty))
        XCTAssertTrue(layout.auxiliaryContentFrame.isEmpty)
    }

    func testAccessoryFramesAreInvalidWhenAllFramesAreZero() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 43)

        XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy(\.isEmpty))
    }

    func testVoiceAndRecordingActionsFailClosedOnShortSurface() {
        for height in [43.0, 54.0, 64.0] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: height)

            XCTAssertTrue(layout.dictateFrame.isEmpty, "height=\(height)")
            XCTAssertTrue(layout.actionRectangles.filter { !$0.isEmpty }.allSatisfy { $0.height >= 44 },
                          "height=\(height), frames=\(layout.actionRectangles)")
        }
    }

    func testSymbolsContentHeightDescribesThreeRealRows() {
        XCTAssertEqual(
            VoiceOnlyKeyboardPolicy.symbolsMinimumContentHeight,
            VoiceOnlyKeyboardPolicy.controlSize * 3
        )
    }

    func testAlternatePagesStayAtNativeHeightWhenThreeRowsFit() {
        XCTAssertEqual(
            VoiceOnlyKeyboardPolicy.alternateMinimumHeight,
            VoiceOnlyKeyboardPolicy.verticalPadding * 2
                + VoiceOnlyKeyboardPolicy.controlSize
                + VoiceOnlyKeyboardPolicy.symbolsMinimumContentHeight
        )
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.alternateMinimumHeight, 216)

        for height in [216.0, 224.0, 228.0] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: height)
            XCTAssertEqual(layout.bottomAuxiliaryControlFrame.minX, layout.surfaceFrame.minX)
            XCTAssertEqual(layout.bottomAuxiliaryControlFrame.width, layout.surfaceFrame.width)
            XCTAssertEqual(layout.bottomAuxiliaryControlFrame.minY,
                           layout.surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.visibleControlGap - VoiceOnlyKeyboardPolicy.controlSize)
            XCTAssertEqual(layout.auxiliaryContentFrame.minY, layout.surfaceFrame.minY)
            XCTAssertEqual(layout.auxiliaryContentFrame.width, layout.surfaceFrame.width)
            XCTAssertEqual(layout.auxiliaryContentFrame.maxY,
                           layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap)
        }

    }

    func testAuxiliaryAccessoryFramesKeepVisibleGapAtRowEdges() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)
        let row = layout.bottomAuxiliaryControlFrame
        let frames = layout.auxiliaryControlFrames

        XCTAssertEqual(frames.first?.minX, row.minX + VoiceOnlyKeyboardPolicy.visibleControlGap)
        XCTAssertLessThanOrEqual(frames.last?.maxX ?? 0, row.maxX - VoiceOnlyKeyboardPolicy.visibleControlGap)
        XCTAssertTrue(frames.allSatisfy { $0.width >= VoiceOnlyKeyboardPolicy.controlSize })
    }

    func testTaskOneUsesInsetSurfaceAndSpacedInBoundsActionGeometry() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.horizontalPadding, 6)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlEdgeInset, 12)
        XCTAssertGreaterThan(VoiceOnlyKeyboardPolicy.railSpacing, 0)

        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 228)
            let bounds = CGRect(x: 0, y: 0, width: width, height: layout.surfaceHeight)
            let rectangles = layout.actionRectangles

            XCTAssertTrue(rectangles.allSatisfy { layout.surfaceFrame.contains($0) }, "width=\(width)")
            XCTAssertTrue(rectangles.allSatisfy { bounds.contains($0) }, "width=\(width)")
            for (index, rectangle) in rectangles.enumerated() {
                for other in rectangles[(index + 1)...] {
                    XCTAssertFalse(rectangle.intersects(other), "width=\(width)")
                }
            }
        }
    }

    func testEmbeddedSurfaceDefinesStableBoundsAndGlobalMicCenter() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 216)
        let expectedSurface = CGRect(x: 6, y: 4, width: 378, height: 208)

        XCTAssertEqual(layout.surfaceFrame, expectedSurface)
        XCTAssertEqual(layout.surfaceInset, 6)
        XCTAssertEqual(layout.centerX, layout.surfaceFrame.midX)
        XCTAssertEqual(layout.auxiliaryContentFrame.minY, layout.surfaceFrame.minY)
        XCTAssertEqual(layout.surfaceFrame.height, VoiceOnlyKeyboardPolicy.surfaceHeight - 8)
    }

    func testRightRailFitsWithinVoiceSurfaceHeight() {
        XCTAssertLessThanOrEqual(
            VoiceOnlyKeyboardPolicy.rightRailHeight,
            VoiceOnlyKeyboardPolicy.surfaceHeight
        )
    }

    func testRailsHideWhenShortSurfaceWouldOverlapDismissAction() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 140)

        XCTAssertEqual(layout.rightRailWidth, 0)
        XCTAssertTrue(layout.dismissFrame.isEmpty)
    }

    func testRightRailUsesDeleteAndReturnWithSeparateDismissAndDictateActions() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailControlCount, 2)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.commandClusterSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailHeight, 88)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)
        XCTAssertEqual(layout.rightRailTop, 12)
        XCTAssertEqual(layout.rightRailBottom, 100)
        XCTAssertEqual(layout.dismissTop, 160)
        XCTAssertEqual(layout.dismissBottom, 204)
        XCTAssertEqual(layout.dismissBottom - layout.dismissTop, 44)
        XCTAssertGreaterThanOrEqual(layout.dismissTop, layout.rightRailBottom)
    }

    func testVoiceSurfaceUsesAvailableWidthAndCentersMicBetweenEqualRails() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)

        XCTAssertEqual(layout.surfaceWidth, 430)
        XCTAssertEqual(layout.leftRailWidth, 140)
        XCTAssertEqual(layout.rightRailWidth, 88)
        XCTAssertEqual(layout.centerX, 215)
    }

    func testVoiceOnlySurfaceDoesNotUseLegacyKeyGrid() {
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.usesLegacyKeyGrid)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.contentHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
    }

    func testAlternateContentUsesTheFullFixedSurfaceForFourUsableRows() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.contentHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)
        XCTAssertEqual(layout.surfaceFrame.minY, VoiceOnlyKeyboardPolicy.verticalPadding)
        XCTAssertEqual(layout.surfaceFrame.height, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.verticalPadding * 2)
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.contentHeight / 4, 44)
    }

    func testAlternateContentUsesTheEntireEmbeddedSurface() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 228)
            let frame = layout.auxiliaryContentFrame

            XCTAssertEqual(frame.minX, layout.surfaceFrame.minX, "width=\(width)")
            XCTAssertEqual(frame.width, layout.surfaceFrame.width, "width=\(width)")
            XCTAssertEqual(frame.minY, layout.surfaceFrame.minY, "width=\(width)")
            XCTAssertEqual(frame.maxY, layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap, "width=\(width)")
            XCTAssertGreaterThanOrEqual(frame.width, layout.centerAreaWidth, "width=\(width)")
        }
    }

    func testSymbolsContentUsesTheFullAlternateContentFrame() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            let frame = layout.auxiliaryContentFrame

            XCTAssertEqual(frame.minX, layout.surfaceFrame.minX, "width=\(width)")
            XCTAssertEqual(frame.width, layout.surfaceFrame.width, "width=\(width)")
            XCTAssertEqual(frame.minY, layout.surfaceFrame.minY, "width=\(width)")
            XCTAssertEqual(frame.maxY, layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap, "width=\(width)")
        }
    }

    func testAuxiliaryModeControlUsesOneCompactUtilityFrame() throws {
        let controller = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)

        XCTAssertEqual(controller.components(separatedBy: "numberButton?.frame = layout.leftUtilityFrames.number").count - 1, 1)
    }

    func testExpandedAlternateSurfaceKeepsLeftUtilitiesVisibleAboveItsContent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controller.contains("setAuxiliaryUtilityVisuals"))
        XCTAssertTrue(controller.contains("configureAuxiliaryAccessoryControls"))
        XCTAssertFalse(rootView.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("let isAuxiliary = mode == .panel || mode == .emoji"))
        XCTAssertTrue(controller.contains("atButton?.isHidden = isAuxiliary || !leftRailVisible"))
        XCTAssertTrue(controller.contains("numberButton?.isHidden = isAuxiliary ? !auxiliaryFramesAvailable : !leftRailVisible"))
    }

    func testAtSitsAboveBottomUtilityRail() {
        for width in [320.0, 375, 390, 430] {
            let frames = VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: width)
            let bottomY = VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.verticalPadding - VoiceOnlyKeyboardPolicy.visibleControlGap - VoiceOnlyKeyboardPolicy.controlSize
            XCTAssertEqual(frames.emoji.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.number.minY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.at.minY, bottomY - VoiceOnlyKeyboardPolicy.controlSize, "width=\(width)")
            XCTAssertEqual(frames.at.maxY, bottomY, "width=\(width)")
            XCTAssertEqual(frames.at.minX, VoiceOnlyKeyboardPolicy.horizontalPadding + VoiceOnlyKeyboardPolicy.visibleControlGap, "width=\(width)")
            XCTAssertEqual(frames.emoji.minX, frames.at.minX, "width=\(width)")
            XCTAssertEqual(frames.number.minX, frames.emoji.maxX + VoiceOnlyKeyboardPolicy.railSpacing, "width=\(width)")
            XCTAssertEqual(Set([frames.at, frames.emoji, frames.number]).count, 3)
        }
    }

    func testAllActionFramesStayWithinBoundsAtRuntimeHeights() {
        for width in [320.0, 375, 390, 430] {
            for height in [64.0, 88, 96, 216] {
                let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: height)
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                let frames = layout.actionRectangles.filter { !$0.isEmpty }
                XCTAssertTrue(frames.allSatisfy(bounds.contains),
                              "width=\(width), height=\(height), frames=\(layout.actionRectangles)")
                XCTAssertTrue(frames.allSatisfy(layout.surfaceFrame.contains),
                              "surface width=\(width), height=\(height), frames=\(frames)")
            }
        }
    }

    func testMicFrameIsEmptyWhenSurfaceCannotContainItsDynamicHeight() {
        for height in [64.0, 70, 88, 96] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: height)
            XCTAssertTrue(layout.surfaceFrame.contains(layout.dictateFrame) || layout.dictateFrame.isEmpty,
                          "height=\(height), frame=\(layout.dictateFrame)")
            if height == 64 { XCTAssertTrue(layout.dictateFrame.isEmpty) }
        }
    }

    func testVisibleControlFramesKeepEightPointGapInsideSurface() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)
        let visibleFrames = [layout.leftUtilityFrames.at, layout.leftUtilityFrames.emoji,
                             layout.leftUtilityFrames.number, layout.deleteFrame,
                             layout.returnFrame, layout.dismissFrame]
        XCTAssertTrue(visibleFrames.allSatisfy { layout.surfaceFrame.insetBy(dx: 8, dy: 8).contains($0) })
    }

    func testDictationErrorFrameIsSeparateAndContainedBelowTheMic() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let policy = try String(
            contentsOf: repository.appending(path: "DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(policy.contains("public var dictationErrorFrame: CGRect"))
    }

    func testDictationErrorLaneRemainsVisibleAtStandardKeyboardHeight() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            let mic = layout.dictateFrame
            let error = layout.dictationErrorFrame
            let rails = layout.actionRectangles.filter { $0 != mic }

            XCTAssertFalse(error.isEmpty, "error lane disappeared at width=\(width)")
            XCTAssertGreaterThanOrEqual(error.height, 20, "error lane is too small at width=\(width)")
            XCTAssertTrue(layout.surfaceFrame.contains(error), "error lane is clipped at width=\(width)")
            XCTAssertFalse(error.intersects(mic), "error lane intersects mic at width=\(width)")
            XCTAssertTrue(rails.allSatisfy { !$0.intersects(error) },
                          "error lane intersects a rail at width=\(width)")
        }
    }

    func testDictationErrorFrameHasVisibleNonIntersectingLaneAtUsableHeights() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            let error = layout.dictationErrorFrame
            let mic = layout.dictateFrame

            XCTAssertFalse(mic.isEmpty, "width=\(width)")
            XCTAssertFalse(error.isEmpty, "width=\(width)")
            XCTAssertTrue(layout.surfaceFrame.contains(error), "width=\(width), error=\(error)")
            XCTAssertFalse(error.intersects(mic), "width=\(width), mic=\(mic), error=\(error)")
            XCTAssertGreaterThanOrEqual(error.height, VoiceOnlyKeyboardPolicy.statusHeight)
            XCTAssertGreaterThanOrEqual(error.minY, mic.maxY + VoiceOnlyKeyboardPolicy.visibleControlGap)
        }
    }

    func testAuxiliaryAccessoryControlsProvideAtLeast44PointHitTargets() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 228)

            XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy { !$0.isEmpty }, "width=\(width)")
            XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy {
                $0.width >= VoiceOnlyKeyboardPolicy.controlSize
                    && $0.height >= VoiceOnlyKeyboardPolicy.controlSize
            }, "width=\(width), frames=\(layout.auxiliaryControlFrames)")
            XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy {
                layout.bottomAuxiliaryControlFrame.contains($0)
            }, "width=\(width)")
        }
    }

    func testStaticAndLayoutHelpersExposeIdenticalFrames() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 216)
        let rails = VoiceOnlyKeyboardPolicy.rightRailFrames(for: 390, surfaceHeight: 216)
        XCTAssertEqual(layout.deleteFrame, rails.delete)
        XCTAssertEqual(layout.returnFrame, rails.returnKey)
        XCTAssertEqual(layout.dismissFrame, VoiceOnlyKeyboardPolicy.dismissFrame(for: 390, surfaceHeight: 216))
        XCTAssertEqual(layout.dismissTop, layout.dismissFrame.minY)
        XCTAssertEqual(layout.dismissBottom, layout.dismissFrame.maxY)
    }

    func testLanguageIndicatorSeparatesReadableVisualWidthFromHitHeight() {
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.languageVisualWidth, 56)
        XCTAssertLessThanOrEqual(VoiceOnlyKeyboardPolicy.languageVisualWidth, 60)
        XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
    }

    func testAlternatePagesUseInsetAbsoluteAuxiliaryGeometry() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)

            XCTAssertEqual(
                layout.bottomAuxiliaryControlFrame,
                CGRect(x: layout.surfaceFrame.minX,
                       y: layout.surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.visibleControlGap - VoiceOnlyKeyboardPolicy.controlSize,
                       width: layout.surfaceFrame.width,
                       height: VoiceOnlyKeyboardPolicy.controlSize),
                "width=\(width)"
            )
            XCTAssertEqual(
                layout.auxiliaryContentFrame,
                CGRect(
                    x: layout.surfaceFrame.minX,
                    y: layout.surfaceFrame.minY,
                    width: layout.surfaceFrame.width,
                    height: layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap - layout.surfaceFrame.minY
                ),
                "width=\(width)"
            )
            XCTAssertTrue(layout.auxiliaryControlFrames.allSatisfy { !$0.isEmpty }, "width=\(width)")
        }
    }

    func testVoiceOnlyRailUsesAppleKeyboardVerticalInsets() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.verticalPadding, 4)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailVerticalPadding, 4)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailHeight, 88)
    }

    func testVoiceOnlySurfaceUsesReferenceHorizontalInsetAndControlGeometry() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.horizontalPadding, 6)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.utilityVisualSize, 36)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.primaryControlSize, 54)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.railSpacing, 4)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlEdgeInset, 12)
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

        XCTAssertEqual(layout.centerX, 215)
        let expectedCenterX = 430.0 / 2.0
        XCTAssertEqual(layout.centerX, expectedCenterX)
    }

    func testVoiceSurfaceKeepsFullRailsCenteredAcrossTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)

            XCTAssertEqual(layout.leftRailWidth, 140, "width=\(width)")
            XCTAssertEqual(layout.rightRailWidth, 88, "width=\(width)")
            XCTAssertGreaterThanOrEqual(layout.centerAreaWidth, 44, "width=\(width)")
            XCTAssertTrue(layout.showsLanguageIndicator, "width=\(width)")
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

        XCTAssertEqual(layout.leftRailWidth, 140)
        XCTAssertEqual(layout.rightRailWidth, 88)
        XCTAssertEqual(layout.centerAreaWidth, 150)
        XCTAssertEqual(layout.centerX, 195)
        XCTAssertEqual(layout.rightRailHeight, 88)
    }

    func testNormalPhoneWidthsKeepThreeUtilityTargetsOutsideCenterSurface() {
        for width in [375.0, 390, 420] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)

            XCTAssertEqual(layout.leftRailWidth, 140, "width=\(width)")
            XCTAssertEqual(layout.rightRailWidth, 88, "width=\(width)")
            XCTAssertEqual(layout.micCenterArea.midX, layout.surfaceFrame.midX, "width=\(width)")
            XCTAssertFalse(layout.micCenterArea.intersects(layout.leftUtilityFrames.number), "width=\(width)")
            XCTAssertFalse(layout.micCenterArea.intersects(layout.rightCommandFrame), "width=\(width)")
        }
    }

    func testSurfaceAndPrimaryContentAreInsetAndContainedAtEverySupportedWidth() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            let bounds = CGRect(x: 0, y: 0, width: width, height: VoiceOnlyKeyboardPolicy.surfaceHeight)
            XCTAssertGreaterThan(layout.surfaceFrame.minX, bounds.minX, "width=\(width)")
            XCTAssertGreaterThan(layout.surfaceFrame.minY, bounds.minY, "width=\(width)")
            XCTAssertLessThan(layout.surfaceFrame.maxX, bounds.maxX, "width=\(width)")
            XCTAssertLessThan(layout.surfaceFrame.maxY, bounds.maxY, "width=\(width)")
            XCTAssertEqual(layout.micCenterArea.midX, layout.surfaceFrame.midX, accuracy: 0.001)
            XCTAssertTrue(layout.surfaceFrame.contains(layout.micCenterArea), "width=\(width)")
            XCTAssertTrue(layout.micCenterArea.contains(layout.dictateFrame), "width=\(width)")
            XCTAssertTrue(layout.surfaceFrame.contains(layout.alternateContentFrame), "width=\(width)")
        }
    }

    func testLayoutUsesTheRuntimeSurfaceHeightForBottomActions() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 216)

        XCTAssertEqual(layout.contentHeight, 216)
            XCTAssertEqual(layout.leftUtilityFrames.at.minY, 116)
            XCTAssertEqual(layout.leftUtilityFrames.number.minY, 160)
            XCTAssertEqual(layout.dismissFrame, CGRect(x: 288, y: 160, width: 88, height: 44))
        XCTAssertLessThanOrEqual(layout.rightRailBottom, layout.dismissFrame.minY)
        XCTAssertTrue(layout.actionRectangles.allSatisfy { $0.maxY <= 216 })
    }

    func testCompactGeometryKeepsGlobalCenterAndAvoidsNarrowOverlap() {
        for width in [375.0, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width)
            XCTAssertEqual(layout.centerX, width / 2)
        }
        let narrow = VoiceOnlyKeyboardPolicy.layout(for: 320)
        let capsule = VoiceOnlyKeyboardPolicy.primaryControlWidth(
            availableWidth: 320,
            centerAreaWidth: narrow.centerAreaWidth
        )
        XCTAssertLessThanOrEqual(160 + capsule / 2, 320 - 12 - 44)
        XCTAssertGreaterThanOrEqual(160 - capsule / 2, 12 + 44 + 4 - 140)
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

        XCTAssertEqual(layout.centerAreaWidth, 68)
        XCTAssertEqual(layout.leftRailWidth, 0)
        XCTAssertEqual(layout.rightRailWidth, 0)
        XCTAssertEqual(layout.horizontalInset, 6)
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
        XCTAssertTrue(VoiceOnlyKeyboardPolicy.layout(for: 320).showsLanguageIndicator)
    }

    func testHiddenRailsHaveNoActionFramesInTheNarrowCenterSurface() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 300)

        XCTAssertEqual(layout.leftRailWidth, 0)
        XCTAssertEqual(layout.rightRailWidth, 0)
        XCTAssertTrue(layout.leftUtilityFrames.at.isEmpty)
        XCTAssertTrue(layout.deleteFrame.isEmpty)
        XCTAssertTrue(layout.returnFrame.isEmpty)
        XCTAssertTrue(layout.dismissFrame.isEmpty)
        XCTAssertEqual(layout.actionRectangles, [layout.dictateFrame])
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

            XCTAssertEqual(rectangles.count, 7, "width=\(width)")
            XCTAssertTrue(rectangles.allSatisfy { $0.minX >= 0 && $0.maxX <= width && $0.minY >= 0 && $0.maxY <= VoiceOnlyKeyboardPolicy.surfaceHeight }, "width=\(width)")
            for (index, rectangle) in rectangles.enumerated() {
                XCTAssertGreaterThanOrEqual(rectangle.width, 44, "index=\(index), width=\(width)")
                if rectangle == layout.dictateFrame {
                    XCTAssertEqual(rectangle.height, VoiceOnlyKeyboardPolicy.primaryControlSize, accuracy: 0.001, "index=\(index), width=\(width)")
                } else {
                XCTAssertTrue(rectangle.height >= 44, "index=\(index), width=\(width)")
                }
                for other in rectangles[(index + 1)...] {
                    XCTAssertFalse(rectangle.intersects(other), "index=\(index), width=\(width)")
                }
            }
            XCTAssertFalse(layout.micCenterArea.intersects(layout.rightCommandFrame))
            XCTAssertEqual(layout.leftBottomCenterX, layout.leftUtilityFrames.emoji.midX)
            XCTAssertEqual(layout.rightBottomCenterX, layout.dismissFrame.midX)
            XCTAssertEqual(layout.leftBottomCenterY, layout.leftUtilityFrames.number.midY)
            XCTAssertEqual(layout.rightBottomCenterY, layout.dismissFrame.midY)
        }
    }

    func testUIKitUtilityFramesFitWithoutOverlapAtTargetWidths() {
        for width in [320.0, 375, 390, 430] {
            let left = VoiceOnlyKeyboardPolicy.leftUtilityFrames(for: width)
            let right = VoiceOnlyKeyboardPolicy.rightRailFrames(for: width)
            let frames = [left.at, left.emoji, left.number,
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

            XCTAssertEqual(layout.languageFrame.minX, layout.surfaceFrame.minX + VoiceOnlyKeyboardPolicy.visibleControlGap, "width=\(width)")
            XCTAssertEqual(layout.languageFrame.minY, VoiceOnlyKeyboardPolicy.verticalPadding + VoiceOnlyKeyboardPolicy.topInset, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.at, left.at, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.emoji, left.emoji, "width=\(width)")
            XCTAssertEqual(layout.leftUtilityFrames.number, left.number, "width=\(width)")
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
        XCTAssertEqual(layout.deleteFrame.minY, 12)
        XCTAssertEqual(layout.dismissFrame.maxY, VoiceOnlyKeyboardPolicy.surfaceHeight - VoiceOnlyKeyboardPolicy.verticalPadding - VoiceOnlyKeyboardPolicy.visibleControlGap)
        XCTAssertEqual(layout.dismissFrame.minY, 160)
        XCTAssertEqual(layout.leftUtilityFrames.at.minY, 116)
        XCTAssertEqual(layout.leftUtilityFrames.number.minY, 160)
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
