import XCTest
@testable import DictusCore

final class DictationHandoffRegressionTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testRequestedKeyboardHandoffAlwaysGetsRetryOrUserVisibleResolution() {
        for appStatus in DictationStatus.allCases {
            let outcome = ColdStartResolutionPolicy.resolution(
                isPending: true,
                storedStatus: .requested,
                coordinatorStatus: appStatus
            )

            XCTAssertTrue(
                outcome == .retry || outcome == .report,
                "requested handoff must not remain silent for app status \(appStatus.rawValue)"
            )
        }
    }

    func testCancelledOrTimedOutKeyboardRequestCannotBeResurrectedByAppRetry() {
        for storedStatus in DictationStatus.allCases where storedStatus != .requested {
            XCTAssertEqual(
                ColdStartResolutionPolicy.resolution(
                    isPending: true,
                    storedStatus: storedStatus,
                    coordinatorStatus: .idle
                ),
                .dropped
            )
        }
    }

    func testKeyboardRootRoutesInputThroughItsOwningControllerCallbacks() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("let routeText: (String) -> Void"))
        XCTAssertTrue(root.contains("let routeCommand: (KeyboardCommand) -> Void"))
        XCTAssertTrue(controller.contains("routeText: { [weak self]"))
        XCTAssertTrue(controller.contains("routeCommand: { [weak self]"))
        XCTAssertFalse(root.contains("state.controller as? KeyboardViewController"),
                      "a cached global controller can be stale after iOS rebuilds the keyboard")
    }

    func testKeyboardProxyRoutingDoesNotRequireTheSharedWeakControllerIdentity() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let textStart = try XCTUnwrap(controller.range(of: "func routeProxyText(_ text: String)"))
        let textEnd = try XCTUnwrap(controller.range(of: "static func routeProxyCommand("))
        let commandStart = try XCTUnwrap(controller.range(of: "func routeProxyCommand(_ command: KeyboardCommand)"))
        let commandEnd = try XCTUnwrap(controller.range(of: "// MARK: - Vendored keyboard owner"))

        let textBody = String(controller[textStart.lowerBound..<textEnd.lowerBound])
        let commandBody = String(controller[commandStart.lowerBound..<commandEnd.lowerBound])
        XCTAssertFalse(textBody.contains("KeyboardState.shared.controller === self"))
        XCTAssertFalse(commandBody.contains("KeyboardState.shared.controller === self"))
        XCTAssertTrue(textBody.contains("isAttached && isOnScreen"))
        XCTAssertTrue(commandBody.contains("isAttached && isOnScreen"))
    }

    func testRuntimeKeyboardFallbackAppliesTheTenPercentSurfaceIncrease() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("fallbackHeight: Double(nativeHeight) * 1.10"),
                      "the policy fallback must be applied to the actual UIKit runtime path")
    }
}
