import XCTest
import Foundation

final class NativeTargetIsolationTests: XCTestCase {
    func testSharedKernelReplacesTheLegacyPackageForEveryConsumer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Dictus.xcodeproj/project.pbxproj"))
        let project = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        let localPaths = objects.values.filter { $0["isa"] as? String == "XCLocalSwiftPackageReference" }
            .compactMap { $0["relativePath"] as? String }
        XCTAssertTrue(localPaths.contains("SyllivraKernel"))
        XCTAssertFalse(localPaths.contains("Dictus" + "Core"))
        for target in objects.values where target["isa"] as? String == "PBXNativeTarget" {
            guard let name = target["name"] as? String,
                  ["DictusApp", "DictusKeyboard", "DictusWidgets"].contains(name) else { continue }
            let dependencies = target["packageProductDependencies"] as? [String] ?? []
            let products = dependencies.compactMap { objects[$0]?["productName"] as? String }
            XCTAssertTrue(products.contains("SyllivraKernel"), name)
            XCTAssertFalse(products.contains("Dictus" + "Core"), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Dictus" + "Core/Package.swift").path))
    }

    func testOnlyTheAppLinksNativeInference() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Dictus.xcodeproj/project.pbxproj"))
        let project = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        var inspected = Set<String>()
        for target in objects.values where target["isa"] as? String == "PBXNativeTarget" {
            guard let name = target["name"] as? String,
                  ["DictusApp", "DictusKeyboard", "DictusWidgets"].contains(name) else { continue }
            inspected.insert(name)
            let dependencies = target["packageProductDependencies"] as? [String] ?? []
            let products = dependencies.compactMap { objects[$0]?["productName"] as? String }
            XCTAssertEqual(products.contains("SyllivraInference"), name == "DictusApp", name)
            let phases = target["buildPhases"] as? [String] ?? []
            let files = phases.flatMap { objects[$0]?["files"] as? [String] ?? [] }
            let linked = files.compactMap { objects[$0]?["productRef"] as? String }
                .compactMap { objects[$0]?["productName"] as? String }
            XCTAssertEqual(linked.contains("SyllivraInference"), name == "DictusApp", name)
        }
        XCTAssertEqual(inspected, ["DictusApp", "DictusKeyboard", "DictusWidgets"])
    }
}
