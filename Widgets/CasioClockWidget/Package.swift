// swift-tools-version:5.9
import PackageDescription

// Experimental, self-contained Home Screen widget: a live clock drawn as a Casio F-91W.
// No dependencies on the app (its only resource is the generated LCD font) — add the library to any widget extension and list
// `CasioClockWidget()` in its WidgetBundle (see README.md).
let package = Package(
    name: "CasioClockWidget",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CasioClockWidget", targets: ["CasioClockWidget"])
    ],
    targets: [
        .target(name: "CasioClockWidget", resources: [.copy("Resources/F91WSegment.ttf")]),
        .testTarget(name: "CasioClockWidgetTests", dependencies: ["CasioClockWidget"]),
    ]
)
