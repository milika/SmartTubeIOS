import SwiftUI

// DSEG7 / DSEG14 Classic Bold Italic by Keshikan (SIL OFL 1.1, Resources/DSEG-LICENSE.txt)
// for digits and letters.

struct LCDFont: Equatable {
    let postScriptName: String
    /// Glyph height as a fraction of the em.
    let glyphToEm: CGFloat
    /// Baseline position from the top of the line box, in ems.
    let baselineFromTop: CGFloat
    /// Advance of one digit, in ems.
    let digitAdvance: CGFloat
    /// A character with every segment lit ("8" / "~"), for the faint unlit segments; nil if none.
    let allSegments: Character?
    /// A digit-wide blank ("!" in DSEG), for an empty leading hour digit.
    let blankDigit: String

    static func dseg7(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG7Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "8", blankDigit: "!")
    }
    static func dseg14(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG14Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "~", blankDigit: "!")
    }

    /// The font whose glyphs are `height` points tall.
    func font(height: CGFloat) -> Font {
        BundledFonts.register()
        return .custom(postScriptName, fixedSize: height / glyphToEm)
    }

    /// `text` with every character replaced by the all-segments glyph (digits by `allSegments`,
    /// keeping colons), for the unlit-segment layer.
    func allLit(_ text: String) -> String? {
        guard let allSegments else { return nil }
        return String(text.map { $0 == ":" ? ":" : allSegments })
    }
}
