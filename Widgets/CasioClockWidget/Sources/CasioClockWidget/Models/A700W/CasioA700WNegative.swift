import SwiftUI
import WidgetKit

// The Casio A700W with a negative (inverted) display: the A700W's face (A700WFace) in black with a
// cyan line and cyan print, the light segments on dark glass glowing when lit (like the W-738H).
// Laid out on the A700W's canvas, measured from a front-on product image of the negative version
// (1100 px, supplied by the owner, measured only): image px = (299.8, 250.5) + 0.8134 × canvas.
enum CasioA700WNegative: CasioModel {
    static let kind = "CasioA700WNegative"
    static let displayName = "Casio A700W Negative"
    static let summary =
        "A live digital clock in the style of the Casio A700W with a negative display. Tap it for the light."

    static let caseExtension = CasioA700W.caseExtension
    static let canvas = CasioA700W.canvas
    static let widgetArea = CasioA700W.widgetArea
    static let caseBackground = CasioA700W.caseBackground

    static func face(_ context: CasioFaceContext) -> some View {
        A700WFace(context: context, palette: palette, layout: layout, display: A700WNegativeDisplay.self, style: lcd)
    }

    /// Colours sampled from the image.
    static let palette = A700WPalette(
        band: Color(white: 0.01), logo: Color(white: 0.50), silver: Color(red: 0.03, green: 0.73, blue: 0.76),
        plate: Color(white: 0.01),
        print: Color(red: 0.10, green: 0.68, blue: 0.70), frame: nil, surround: Color(white: 0.01),
        labelBox: nil, separator: .clear,
        labels: Array(repeating: Color(red: 0.10, green: 0.68, blue: 0.70), count: 4))

    /// Measured on the negative version's image.
    static let layout = A700WGeometry(
        band: CGRect(x: 43, y: 126.5, width: 517.5, height: 411),
        line: CGRect(x: 64, y: 176, width: 479.5, height: 318.5), lineWidth: 8, lineFilled: false,
        casio: CGRect(x: 248.5, y: 144, width: 112, height: 20),
        water: CGRect(x: 176.5, y: 200.5, width: 82, height: 13.5),
        wrBox: CGRect(x: 266, y: 193.5, width: 76.5, height: 27),
        wr: CGRect(x: 279, y: 199.5, width: 51, height: 15), resist: CGRect(x: 350, y: 200, width: 82, height: 14),
        frame: CGRect(x: 120, y: 252.5, width: 364.5, height: 185),
        glass: CGRect(x: 128, y: 258, width: 348.5, height: 171.5),
        lightSquare: CGRect(x: 118.5, y: 442, width: 12, height: 12.5),
        light: CGRect(x: 142.5, y: 441.5, width: 59.5, height: 14),
        modeSquare: CGRect(x: 118, y: 461, width: 12.5, height: 12),
        mode: CGRect(x: 142.5, y: 460, width: 61, height: 14),
        startStop: CGRect(x: 233.8, y: 460.5, width: 229.9, height: 14),
        rightSquare: CGRect(x: 474.9, y: 461.6, width: 12.3, height: 12.3),
        alarmChronograph: CGRect(x: 160.2, y: 502.2, width: 284, height: 20.8),
        labels: [
            CGRect(x: 137.5, y: 231, width: 64, height: 16.5), CGRect(x: 230.5, y: 231, width: 42.5, height: 16.5),
            CGRect(x: 311, y: 231, width: 50, height: 16.5), CGRect(x: 389.5, y: 231, width: 78, height: 16.5),
        ])

    /// Light segments on dark glass; lit, the segments glow.
    static let lcd = LCDStyle(
        digits: .casio("A700WNegative"),
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.19, green: 0.21, blue: 0.26),
        ink: Color(red: 0.65, green: 0.70, blue: 0.62),
        shadow: LCDShadow(edgeOpacity: 0.5, edgeWidth: 9, segmentOpacity: 0.08),
        litInk: Color(red: 0.86, green: 0.96, blue: 1.0))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("A700W Negative", as: .systemSmall) {
    CasioWatchWidget<CasioA700WNegative>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
