// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FocusGuard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FocusCore"),
        .executableTarget(name: "focus-check", dependencies: ["FocusCore"]),
    ],
    swiftLanguageModes: [.v5]
)
