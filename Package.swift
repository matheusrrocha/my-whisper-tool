// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperFlow",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperFlow"
        ),
        .testTarget(
            name: "WhisperFlowTests",
            dependencies: ["WhisperFlow"],
            path: "Tests/WhisperFlowTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
