// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShotGenie",
    platforms: [.macOS("26.0")],
    targets: [
        // Lógica pura, sin AppKit: se prueba con `swift test`.
        .target(name: "ShotGenieCore"),
        .executableTarget(name: "ShotGenie", dependencies: ["ShotGenieCore"]),
        .testTarget(name: "ShotGenieCoreTests", dependencies: ["ShotGenieCore"]),
    ],
    swiftLanguageModes: [.v5]
)
