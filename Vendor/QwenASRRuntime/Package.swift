// swift-tools-version: 5.9
import PackageDescription

// Only the ASR/VAD modules are shipped. No server, CLI, TTS or binary downloads.
let package = Package(
    name: "QwenASRRuntime",
    platforms: [.iOS(.v17), .macOS("15.0")],
    products: [.library(name: "Qwen3ASR", targets: ["Qwen3ASR"]),
               .library(name: "SpeechVAD", targets: ["SpeechVAD"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.6"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.9")
    ],
    targets: [
        .target(name: "AudioCommon", dependencies: [.product(name: "Hub", package: "swift-transformers")]),
        .target(name: "MLXCommon", dependencies: ["AudioCommon", .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"), .product(name: "MLXFast", package: "mlx-swift")]),
        .target(name: "SpeechVAD", dependencies: ["AudioCommon", "MLXCommon",
            .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift")]),
        .target(name: "Qwen3ASR", dependencies: ["AudioCommon", "MLXCommon", "SpeechVAD",
            .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift")]),
        .testTarget(name: "CancellationTests", dependencies: ["Qwen3ASR",
            .product(name: "MLX", package: "mlx-swift")], path: "Tests")
    ]
)
