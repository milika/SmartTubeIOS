import SwiftUI

// Laid out on a fixed 594×530 canvas whose coordinates were measured from a front-on photo of
// an F-91W (Wikimedia Commons, Casio_F-91W_5051.jpg), then scaled to the widget.
// Typefaces per Fonts In Use (fontsinuse.com/uses/74290): CASIO logo Microgramma; "F-91W"
// Neue Helvetica Extended Black; "ALARM CHRONOGRAPH" regular-width Medium; the other labels
// Eurostile Extended Regular / Medium. Free look-alikes (SIL OFL, Google Fonts) stand in:
// Michroma for Microgramma / Eurostile Extended, Archivo Expanded Black (an instance of
// Archivo's variable font) for Neue Helvetica Extended Black, Saira Medium for Eurostile Medium,
// Saira Expanded SemiBold (an instance of Saira's variable font) for the WR mark.
enum CasioF91W: CasioComplicationModel {
    /// The original widget's kind, kept so widgets already on Home Screens survive updates.
    static let kind = "CasioClockWidget"
    static let displayName = "Casio F-91W"
    static let summary = "A live digital clock in the style of the Casio F-91W. Tap it for the light."
    static let canvas = CGSize(width: 594, height: 530)
    static let fonts = [
        "DSEG7Classic-BoldItalic", "DSEG14Classic-BoldItalic", "Michroma-Regular", "ArchivoExpanded-Black",
        "Saira-Medium", "SairaExpanded-SemiBold",
    ]

    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { F91WFace(context: context) }

    static let complicationKind = "CasioF91WComplication"
    static let complicationName = "Casio F-91W"
    static let complicationSummary = "The F-91W's display: time with live seconds, day and date."

    static func rectangularComplication(_ context: CasioFaceContext) -> some View {
        F91WComplication(context: context)
    }

    // Colours sampled from the photo, white-balanced so the white print is neutral.
    static let blue = Color(red: 0.04, green: 0.45, blue: 0.95)
    static let silver = Color(white: 0.86)
    static let gold = Color(red: 0.90, green: 0.78, blue: 0.40)
    static let printWhite = Color(white: 0.94)
    static let red = Color(red: 0.95, green: 0.13, blue: 0.13)

    /// The LCD: DSEG Bold Italic with faint unlit segments on grey-green glass (LCDStyle's defaults).
    static let lcd = LCDStyle()
    /// Width of the big digits relative to DSEG's (measured from the photo).
    static let digitSqueeze: CGFloat = 0.9

    // Case print fonts (Resources/).
    static func michroma(_ size: CGFloat) -> Font { CaseFont.custom("Michroma-Regular", size) }
    static func archivoBlack(_ size: CGFloat) -> Font { CaseFont.custom("ArchivoExpanded-Black", size) }
    static func saira(_ size: CGFloat) -> Font { CaseFont.custom("Saira-Medium", size) }
    static func sairaExpanded(_ size: CGFloat) -> Font { CaseFont.custom("SairaExpanded-SemiBold", size) }
}
