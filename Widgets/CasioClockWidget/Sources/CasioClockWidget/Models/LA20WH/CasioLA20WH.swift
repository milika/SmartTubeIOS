import SwiftUI
import WidgetKit

// The Casio LA-20WH-1B: a small black resin case with ILLUMINATOR and WATER RESIST in white, a
// black face inside a white line and a slate-blue one, CASIO, START/STOP and ALARM CHRONO, the
// inverted (negative) LCD in a white rim (LA20WHDisplay), MODE, LIGHT and the WR badge. Laid out on
// a canvas measured from a front-on product image the owner supplied (500 × 600 px, measured
// only, not shipped): image px = (110, 160) + 0.5 × canvas.
enum CasioLA20WH: CasioModel {
    static let kind = "CasioLA20WH"
    static let displayName = "Casio LA-20WH"
    static let summary = "A live digital clock in the style of the Casio LA-20WH. Tap it for the light."

    static let canvas = CGSize(width: 560, height: 600)
    /// The case from its top edge to its bottom, centred on the face.
    static let widgetArea = CGRect(x: 71, y: 58, width: 402, height: 402)

    /// Black resin.
    static let caseBackground = Color(white: 0.17)

    static func face(_ context: CasioFaceContext) -> some View { LA20WHFace(context: context) }

    // Colours sampled from the image.
    static let resin = Color(white: 0.17)
    static let resinEdge = Color(white: 0.30)
    static let chrome = Color(white: 0.85)
    static let face = Color(red: 0.01, green: 0.0, blue: 0.012)
    static let printWhite = Color(white: 0.92)
    static let slate = Color(red: 0.39, green: 0.45, blue: 0.53)
    /// The slate line around the face is shaded darker than the slate print.
    static let slateLine = Color(red: 0.28, green: 0.32, blue: 0.38)

    /// Inverted: light segments on black glass; lit, the segments glow.
    static let lcd = LCDStyle(
        digits: .casio("LA20WH"), letters: .dseg7("BoldItalic"), glass: Color(white: 0.02),
        ink: Color(red: 0.86, green: 0.85, blue: 0.87),
        shadow: LCDShadow(edgeOpacity: 0, segmentOpacity: 0.05),
        litInk: Color(red: 0.80, green: 0.97, blue: 1.0))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("LA-20WH", as: .systemSmall) {
    CasioWatchWidget<CasioLA20WH>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
