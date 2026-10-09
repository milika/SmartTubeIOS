import CoreText
import Foundation

/// Registers every font in the package's resources once, for all models.
enum BundledFonts {
    static func register() { _ = registered }

    private static let registered: Bool = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()
}
