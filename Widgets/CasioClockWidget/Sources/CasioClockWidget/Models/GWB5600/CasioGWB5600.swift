import SwiftUI
import WidgetKit

// The Casio G-Shock GW-B5600 (Midnight Green, GW-B5600MG), its face without the PROTECTION /
// G-SHOCK bezel: a black face with a green camouflage print, a blue-grey panel around the display,
// white and mint print, and GWB5600Display. Laid out on a canvas measured from a front-on product
// image supplied by the owner (measured only): canvas = image (1200 px) − (270, 420), before the
// case extension.
enum CasioGWB5600: CasioModel {
    static let kind = "CasioGWB5600"
    static let displayName = "G-Shock GW-B5600"
    static let summary = "A live digital clock in the style of the G-Shock GW-B5600. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (elements keep
    /// their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 74
    static let canvas = CGSize(width: 660, height: 600 + caseExtension)
    /// The black face.
    static let widgetArea = CGRect(x: 8, y: 12, width: 609, height: 609)

    /// Behind the face: its black (shows in the face's cut corners).
    static let caseBackground = Color(red: 0.02, green: 0.02, blue: 0.05)

    static func face(_ context: CasioFaceContext) -> some View { GWB5600Face(context: context) }

    // Colours sampled from the image.
    static let face = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let camo = Color(red: 0.07, green: 0.17, blue: 0.12)
    static let panel = Color(red: 0.25, green: 0.32, blue: 0.36)
    static let printWhite = Color(white: 0.90)
    static let mint = Color(red: 0.10, green: 0.72, blue: 0.58)

    /// Italic 7-segment digits and letters on pale grey glass; a white LED.
    static let lcd = LCDStyle(
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.65, green: 0.67, blue: 0.64), ink: Color(white: 0.08),
        backlight: Color(red: 0.86, green: 0.95, blue: 1.0), backlightFalloff: [0.85, 0.85, 0.85])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("GW-B5600", as: .systemSmall) {
    CasioWatchWidget<CasioGWB5600>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
