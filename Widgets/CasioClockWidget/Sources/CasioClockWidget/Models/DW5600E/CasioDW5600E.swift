import SwiftUI
import WidgetKit

// The Casio G-Shock DW-5600E: black resin bezel with PROTECTION and G-SHOCK, a black face with a white
// rounded-octagon line, CASIO / ILLUMINATOR / WATER 200M RESIST above the module-3229 display
// (Module3229Display), ELECTRO LUMINESCENT BACKLIGHT and ALARM [SHOCK RESIST] CHRONO below, and a
// blue-green EL light. Laid out on a canvas measured from a front-on product image supplied by the
// owner (measured only): canvas = image (2000 px) − (540, 580).
enum CasioDW5600E: CasioModel {
    static let kind = "CasioDW5600E"
    static let displayName = "G-Shock DW-5600E"
    static let summary = "A live digital clock in the style of the G-Shock DW-5600E. Tap it for the light."

    static let canvas = CGSize(width: 860, height: 700)
    /// The bezel from PROTECTION to G-SHOCK, square.
    static let widgetArea = CGRect(x: 105, y: 20, width: 660, height: 660)

    /// Black resin.
    static let caseBackground = Color(white: 0.10)

    static func face(_ context: CasioFaceContext) -> some View { DW5600EFace(context: context) }

    // Colours sampled from the image.
    static let bezel = Color(white: 0.14)
    static let bezelEdge = Color(white: 0.20)
    static let face = Color(white: 0.06)
    static let printWhite = Color(white: 0.85)
    static let gold = Color(red: 0.62, green: 0.53, blue: 0.36)
    static let blue = Color(red: 0.42, green: 0.57, blue: 0.62)
    static let red = Color(red: 0.42, green: 0.13, blue: 0.16)

    /// Module 3229: italic 7-segment digits and letters on pale grey-green glass; EL light.
    static let lcd = LCDStyle(
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.72, green: 0.77, blue: 0.74), ink: Color(white: 0.09),
        backlight: Color(red: 0.55, green: 0.95, blue: 0.92), backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("DW-5600E", as: .systemSmall) {
    CasioWatchWidget<CasioDW5600E>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
