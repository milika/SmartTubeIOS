import SwiftUI
import WidgetKit

// The Casio A178W: a chrome case with a black face in a silver ring, a large LCD in a white
// outline (A178WDisplay), CASIO, ◀ILLUMINATOR▶ and ALARM CHRONO above, ADJUST / MODE / LIGHT /
// START/STOP beside it, and the blue WR, DUAL TIME and 10YEAR BATTERY below. Laid out on a canvas
// measured from a front-on product image (A178WA-1A, 1000 px, supplied by the owner, measured
// only): image px = (250, 215) + 0.8 × canvas.
enum CasioA178W: CasioModel {
    static let kind = "CasioA178W"
    static let displayName = "Casio A178W"
    static let summary = "A live digital clock in the style of the Casio A178W. Tap it for the light."

    /// The face is about square; no case extension.
    static let caseExtension: CGFloat = 0
    static let canvas = CGSize(width: 640, height: 640)
    /// The face, its silver ring and a strip of the chrome case.
    static let widgetArea = CGRect(x: 49, y: 65, width: 488, height: 488)

    /// Polished steel.
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.88), Color(white: 0.66), Color(white: 0.82), Color(white: 0.60), Color(white: 0.74)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { A178WFace(context: context) }

    // Colours sampled from the image.
    static let ring = Color(red: 0.60, green: 0.72, blue: 0.73)
    static let plate = Color(red: 0.09, green: 0.11, blue: 0.13)
    static let outline = Color(red: 0.96, green: 0.99, blue: 0.99)
    static let printWhite = Color(red: 0.76, green: 0.83, blue: 0.85)
    static let blue = Color(red: 0.31, green: 0.51, blue: 0.71)

    /// Thin upright 7-segment digits (DSEG Light) on pale grey-green glass; the EL panel glows
    /// blue-green.
    static let lcd = LCDStyle(
        digits: .casio("A178W"), letters: .dseg7("Light"), glass: Color(red: 0.64, green: 0.66, blue: 0.60),
        ink: Color(red: 0.08, green: 0.09, blue: 0.12), backlight: Color(red: 0.55, green: 0.95, blue: 0.92),
        backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("A178W", as: .systemSmall) {
    CasioWatchWidget<CasioA178W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
