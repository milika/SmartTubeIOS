// swift-tools-version:5.9
import PackageDescription

// Experimental, self-contained Home Screen widget: a live clock drawn as a Casio F-91W.
// No dependencies on the app — add the library to any widget extension and list
// `CasioClockWidget()` in its WidgetBundle (see README.md).
let package = Package(
    name: "CasioClockWidget",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CasioClockWidget", targets: ["CasioClockWidget"])
    ],
    targets: [
        .target(name: "CasioClockWidget"),
        .testTarget(name: "CasioClockWidgetTests", dependencies: ["CasioClockWidget"]),
    ]
)
