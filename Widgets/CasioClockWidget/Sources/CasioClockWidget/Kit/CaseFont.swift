import SwiftUI

/// Fonts for text printed on a watch case, by PostScript name (bundled in Resources/).
enum CaseFont {
    static func custom(_ postScriptName: String, _ size: CGFloat) -> Font {
        BundledFonts.register()
        return .custom(postScriptName, fixedSize: size)
    }
}
