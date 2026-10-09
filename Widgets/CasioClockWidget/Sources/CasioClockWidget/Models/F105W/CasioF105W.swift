import SwiftUI
import WidgetKit

// The Casio F-105W: black resin, a blue octagon line around a black face, CASIO and ALARM CHRONO,
// a blue panel with the ILLUMINATOR band, the LCD in a black frame (F105WDisplay), the beige EL
// BACKLIGHT/RESET plate, MODE and START·STOP/12·24HR, and WATER RESIST. Laid out on a canvas
// measured from a front-on product image (F-105W-1A, 1000 px, supplied by the owner, measured
// only): image px = (250, 230) + 0.75 × canvas, before the case extension.
enum CasioF105W: CasioModel {
    static let kind = "CasioF105W"
    static let displayName = "Casio F-105W"
    static let summary = "A live digital clock in the style of the Casio F-105W. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (elements keep
    /// their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 51.5
    static let canvas = CGSize(width: 640, height: 640 + caseExtension)
    /// The face inside the case's moulded edge.
    static let widgetArea = CGRect(x: 61.5, y: 79, width: 520, height: 520)

    /// Black resin.
    static let caseBackground = Color(red: 0.19, green: 0.21, blue: 0.22)

    static func face(_ context: CasioFaceContext) -> some View { F105WFace(context: context) }

    // Colours sampled from the image.
    static let bevel = Color(red: 0.32, green: 0.34, blue: 0.34)
    static let ring = Color(red: 0.03, green: 0.43, blue: 0.67)
    static let face = Color(red: 0.06, green: 0.08, blue: 0.08)
    static let panel = Color(red: 0.01, green: 0.36, blue: 0.58)
    static let frame = Color(red: 0.05, green: 0.08, blue: 0.05)
    static let printWhite = Color(red: 0.81, green: 0.82, blue: 0.82)
    static let illuminator = Color(red: 0.83, green: 0.88, blue: 0.93)
    static let labelBlue = Color(red: 0.65, green: 0.75, blue: 0.85)
    static let beige = Color(red: 0.90, green: 0.88, blue: 0.81)
    static let brown = Color(red: 0.25, green: 0.20, blue: 0.12)

    /// Upright 7-segment digits on pale green glass; the EL panel glows blue-green.
    static let lcd = LCDStyle(
        digits: .dseg7("Bold"), letters: .dseg7("Bold"), glass: Color(red: 0.71, green: 0.76, blue: 0.67),
        ink: Color(red: 0.05, green: 0.06, blue: 0.02), backlight: Color(red: 0.55, green: 0.95, blue: 0.92),
        backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("F-105W", as: .systemSmall) {
    CasioWatchWidget<CasioF105W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
