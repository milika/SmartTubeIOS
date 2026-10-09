import SwiftUI

/// Fonts for text printed on a watch case, by PostScript name (bundled in Resources/).
enum CaseFont {
    // The bundled case fonts' PostScript names, spelled only here (a misspelt name would fall
    // back to the system font without an error).
    static let michroma = "Michroma-Regular"
    static let saira = "Saira-Medium"
    static let sairaExpanded = "SairaExpanded-SemiBold"
    static let archivoBlack = "ArchivoExpanded-Black"
    static let all = [michroma, saira, sairaExpanded, archivoBlack]

    static func custom(_ postScriptName: String, _ size: CGFloat) -> Font {
        BundledFonts.register()
        return .custom(postScriptName, fixedSize: size)
    }
}
