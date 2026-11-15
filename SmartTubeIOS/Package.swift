// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SmartTubeIOS",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
    ],
    products: [
        // Cross-platform core: models + InnerTube/SponsorBlock services (Foundation only).
        .library(
            name: "SmartTubeIOSCore",
            targets: ["SmartTubeIOSCore"]
        ),
        // SwiftUI UI layer (iOS/iPadOS/macOS).
        .library(name: "SmartTubeIOS", targets: ["SmartTubeIOS"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk",
            from: "12.0.0"
        ),

    ],
    targets: [
        // MARK: Core – iOS, macOS (Foundation only)
        .target(
            name: "SmartTubeIOSCore",
            dependencies: [],
            path: "Sources/SmartTubeIOSCore",
            resources: [
                // Single catalog for every target: app, extensions, widget and both libraries.
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: UI – iOS/iPadOS/macOS (SwiftUI)
        .target(
            name: "SmartTubeIOS",
            dependencies: [
                "SmartTubeIOSCore",
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
            ],
            path: "Sources/SmartTubeIOS",
            resources: [
                .copy("Resources/yt.solver.lib.min.js"),
                .copy("Resources/yt.solver.core.min.js"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: Tests
        .testTarget(
            name: "SmartTubeIOSTests",
            dependencies: ["SmartTubeIOSCore", "SmartTubeIOS"],
            path: "Tests/SmartTubeIOSTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
