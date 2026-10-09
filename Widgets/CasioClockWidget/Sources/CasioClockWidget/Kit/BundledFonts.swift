import CoreText
import Foundation

/// Registers every font in the package's resources once, for all models.
enum BundledFonts {
    static func register() { _ = registered }

    /// The font files in Resources/.
    static var fileURLs: [URL] { Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] }

    private static let registered: Bool = {
        for url in fileURLs {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()
}
