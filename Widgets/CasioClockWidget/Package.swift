// swift-tools-version:5.9
import PackageDescription

// Experimental, self-contained Home Screen widgets: live clocks drawn as Casio watches, one
// widget per model (README.md lists them). No dependencies on the app; resources are fonts.
// Add the library to a widget extension and list the widgets in its WidgetBundle (README.md).
let package = Package(
    name: "CasioClockWidget",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "CasioClockWidget", targets: ["CasioClockWidget"])
    ],
    targets: [
        .target(name: "CasioClockWidget", resources: [.process("Resources")]),
        .testTarget(name: "CasioClockWidgetTests", dependencies: ["CasioClockWidget"]),
    ]
)
