import SwiftUI
import WidgetKit

// The Casio A700W: a slim chrome case, a black band with CASIO and ALARM CHRONOGRAPH, a grey plate
// in a silver line with WATER [WR] RESIST and the button labels, and the LCD window with its
// coloured ALARM / SIG / SPL / CHRONO labels (A700WDisplay). Laid out on a canvas measured from a
// front-on product image (A700WE-1A, 1000 px, supplied by the owner, measured only): image px =
// (240, 205) + 0.8 × canvas, before the case extension. The negative version (CasioA700WNegative)
// draws the same face in its colours.
enum CasioA700W: CasioModel {
    static let kind = "CasioA700W"
    static let displayName = "Casio A700W"
    static let summary = "A live digital clock in the style of the Casio A700W. Tap it for the light."

    /// The face is much wider than tall; the case is extended until the widget is square (elements
    /// keep their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 114.5
    static let canvas = CGSize(width: 640, height: 640 + caseExtension)
    /// The black band and a strip of the chrome case.
    static let widgetArea = CGRect(x: 25.5, y: 114.5, width: 555, height: 555)

    /// Polished steel.
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.92), Color(white: 0.70), Color(white: 0.86), Color(white: 0.64), Color(white: 0.78)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View {
        A700WFace(context: context, palette: palette, layout: layout, display: A700WDisplay.self, style: lcd)
    }

    /// Colours sampled from the image.
    static let palette = A700WPalette(
        band: Color(red: 0.03, green: 0.03, blue: 0.07), logo: Color(white: 0.84), silver: Color(white: 0.75),
        plate: Color(red: 0.27, green: 0.27, blue: 0.28), print: Color(white: 0.84),
        frame: Color(white: 0.57), surround: Color(red: 0.41, green: 0.46, blue: 0.49),
        labelBox: Color(white: 0.09), separator: Color(white: 0.58),
        labels: [
            Color(red: 0.20, green: 0.70, blue: 0.78), Color(red: 0.70, green: 0.70, blue: 0.45),
            Color(red: 0.25, green: 0.68, blue: 0.52), Color(red: 0.80, green: 0.36, blue: 0.68),
        ])

    /// Measured on the A700WE image.
    static let layout = A700WGeometry(
        band: CGRect(x: 35.5, y: 124.5, width: 535, height: 420.5),
        line: CGRect(x: 57, y: 173.5, width: 494.5, height: 329), lineWidth: 6.75, lineFilled: true,
        casio: CGRect(x: 250.5, y: 140.5, width: 112.5, height: 22.5),
        water: CGRect(x: 180, y: 189.5, width: 81.5, height: 15.5),
        wrBox: CGRect(x: 270, y: 184, width: 72, height: 26),
        wr: CGRect(x: 282, y: 190, width: 48, height: 14), resist: CGRect(x: 351, y: 189.5, width: 81, height: 16),
        frame: CGRect(x: 96.5, y: 211.5, width: 413, height: 241),
        glass: CGRect(x: 128, y: 257, width: 354, height: 176.5),
        lightSquare: CGRect(x: 120.5, y: 458.5, width: 12, height: 12),
        light: CGRect(x: 144, y: 458, width: 60, height: 14.5),
        modeSquare: CGRect(x: 120.5, y: 475.5, width: 12, height: 12),
        mode: CGRect(x: 143, y: 474.5, width: 61, height: 15),
        startStop: CGRect(x: 234.5, y: 474.5, width: 225.5, height: 15),
        rightSquare: CGRect(x: 471.5, y: 477, width: 12, height: 11.5),
        alarmChronograph: CGRect(x: 162, y: 511, width: 278.5, height: 19.5),
        labels: [
            CGRect(x: 138, y: 230.5, width: 59, height: 16), CGRect(x: 230.5, y: 231.5, width: 42, height: 14),
            CGRect(x: 313, y: 231, width: 48, height: 15), CGRect(x: 394.5, y: 230, width: 73, height: 16.5),
        ])

    /// Italic 7-segment digits on pale grey glass; the EL panel glows blue-green.
    static let lcd = LCDStyle(
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.65, green: 0.65, blue: 0.61), ink: Color(white: 0.05),
        backlight: Color(red: 0.55, green: 0.95, blue: 0.92), backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("A700W", as: .systemSmall) {
    CasioWatchWidget<CasioA700W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
