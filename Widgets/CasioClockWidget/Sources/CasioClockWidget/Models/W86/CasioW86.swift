import SwiftUI
import WidgetKit

// The Casio W-86: black resin with a grey inner ring, a black face with the teal ELECTRO
// LUMINESCENCE band and stripes, a grey frame around the LCD (W86Display), the teal ILLUMINATOR
// band and WATER 50M RESIST, and a blue EL light. Laid out on a canvas measured from a front-on
// photo (Wikimedia Commons, `Casio W-86 digital watch (front closeup minor retouch).jpg`,
// Multicherry, CC BY-SA 4.0): image (1920 px) px = (435, 390) + 1.5 × canvas, before the case
// extension. Colours are corrected for the photo's blue cast.
enum CasioW86: CasioModel {
    static let kind = "CasioW86"
    static let displayName = "Casio W-86"
    static let summary = "A live digital clock in the style of the Casio W-86. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (elements keep
    /// their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 122
    static let canvas = CGSize(width: 720, height: 640 + caseExtension)
    /// The face inside the grey ring.
    static let widgetArea = CGRect(x: 7.5, y: 26.5, width: 701.5, height: 701.5)

    /// Black resin.
    static let caseBackground = Color(white: 0.16)

    static func face(_ context: CasioFaceContext) -> some View { W86Face(context: context) }

    // Colours sampled from the photo, corrected for its blue cast.
    static let ring = Color(white: 0.36)
    static let plate = Color(white: 0.05)
    static let frame = Color(white: 0.40)
    static let teal = Color(red: 0.33, green: 0.78, blue: 0.70)
    static let printWhite = Color(white: 0.92)
    static let red = Color(red: 0.86, green: 0.20, blue: 0.24)

    /// Italic 7-segment digits on pale grey glass; the EL panel glows ice-blue (photo of it lit).
    static let lcd = LCDStyle(
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.72, green: 0.74, blue: 0.69), ink: Color(white: 0.12),
        backlight: Color(red: 0.55, green: 0.86, blue: 1.0), backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("W-86", as: .systemSmall) {
    CasioWatchWidget<CasioW86>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
