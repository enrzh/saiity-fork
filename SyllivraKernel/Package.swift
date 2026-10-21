// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyllivraKernel",
    platforms: [.iOS(.v17), .macOS("26.0")],
    products: [
        .library(name: "SyllivraKernel", targets: ["SyllivraKernel"]),
        .executable(name: "polish-harness", targets: ["polish-harness"])
    ],
    targets: [
        .target(name: "SyllivraKernel", path: "Sources/SyllivraKernel"),
        // Off-device polish eval harness (macOS only — needs Apple Intelligence).
        // Runs the REAL pipeline (PolishPipeline + AppleFoundationModelsPolishEngine)
        // on text fixtures, sharing one source of truth with the app. Not built by
        // the iOS app or CI; run locally on a Mac with Apple Intelligence enabled.
        .executableTarget(
            name: "polish-harness",
            dependencies: ["SyllivraKernel"],
            path: "Sources/polish-harness",
            exclude: ["README.md"],
            resources: [.copy("fixtures")]
        ),
        .testTarget(
            name: "SyllivraKernelTests",
            dependencies: ["SyllivraKernel"],
            path: "Tests/SyllivraKernelTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
