import SwiftUI
import WidgetKit

// The Casio G-Shock DW-5600E, its face without the PROTECTION / G-SHOCK bezel: a black face with a white
// rounded-octagon line, CASIO / ILLUMINATOR / WATER 200M RESIST above the module-3229 display
// (Module3229Display), ELECTRO LUMINESCENT BACKLIGHT and ALARM [SHOCK RESIST] CHRONO below, and a
// blue-green EL light. Laid out on a canvas measured from a front-on product image supplied by the
// owner (measured only): canvas = image (2000 px) − (540, 580).
enum CasioDW5600E: CasioModel {
    static let kind = "CasioDW5600E"
    static let displayName = "G-Shock DW-5600E"
    static let summary = "A live digital clock in the style of the G-Shock DW-5600E. Tap it for the light."

    /// The widget shows the black face without the resin bezel (owner: G-Shocks don't need the big
    /// bezel). The face is wider than tall, so the case is extended until it is square (elements
    /// keep their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 80
    static let canvas = CGSize(width: 860, height: 700 + caseExtension)
    /// The black face.
    static let widgetArea = CGRect(x: 136, y: 108, width: 600, height: 600)

    /// Behind the face: its black (shows in the face's cut corners).
    static let caseBackground = Color(white: 0.06)

    static func face(_ context: CasioFaceContext) -> some View { DW5600EFace(context: context) }

    // Colours sampled from the image.
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
