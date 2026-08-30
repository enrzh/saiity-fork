import XCTest

final class FloatingTabBarLayoutContractTests: XCTestCase {
    func testFloatingTabBarAvoidanceBelongsToEachTabNavigationContent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainTabView = try String(
            contentsOf: repository.appending(path: "DictusApp/Views/MainTabView.swift"),
            encoding: .utf8
        )
        let pageViews = try ["HomeView", "ModelManagerView", "SettingsView"].map { name in
            try String(
                contentsOf: repository.appending(path: "DictusApp/Views/\(name).swift"),
                encoding: .utf8
            )
        }

        XCTAssertEqual(mainTabView.components(separatedBy: ".safeAreaInset(edge: .bottom").count - 1, 3)
        XCTAssertTrue(pageViews.allSatisfy { !$0.contains(".safeAreaInset(edge: .bottom") })
    }
}
