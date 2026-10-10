import SwiftUI
import WidgetKit

// The Casio W-738H with the inverted (negative) display the owner chose: black resin, a grained
// octagon bezel, VIBRATION ALARM above and a LIGHT button below, a black face with a white
// cut-corner line, and light segments on near-black glass (W738HDisplay). Laid out on a canvas
// measured from a front-on image supplied by the owner (measured only):
// canvas = image (1200 px) − (280, 180). The whole front fits the square widget.
enum CasioW738H: CasioModel {
    static let kind = "CasioW738H"
    static let displayName = "Casio W-738H"
    static let summary =
        "A live digital clock in the style of the Casio W-738H with a negative display. Tap it for the light."

    static let canvas = CGSize(width: 640, height: 660)
    /// The bezel with 14 pt of the case around (as the A158W); VIBRATION ALARM and the LIGHT button
    /// are left out.
    static let widgetArea = CGRect(x: 82, y: 89, width: 475, height: 475)

    static let caseBackground = Color(white: 0.15)

    static func face(_ context: CasioFaceContext) -> some View { W738HFace(context: context) }

    // Colours sampled from the image.
    static let bezel = Color(white: 0.20)
    static let bezelEdge = Color(white: 0.30)
    static let face = Color(white: 0.06)
    static let faceLine = Color(white: 0.74)
    static let printWhite = Color(white: 0.90)
    static let caseGrey = Color(white: 0.62)
    static let button = Color(white: 0.12)

    /// Inverted: light grey segments on near-black glass; lit, the segments glow cool white.
    static let lcd = LCDStyle(
        digits: .casio("W738H"),
        letters: .dseg7("BoldItalic"), glass: Color(white: 0.11), ink: Color(red: 0.72, green: 0.72, blue: 0.69),
        shadow: LCDShadow(edgeOpacity: 0.5, edgeWidth: 9, segmentOpacity: 0.08),
        litInk: Color(red: 0.86, green: 0.96, blue: 1.0))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("W-738H", as: .systemSmall) {
    CasioWatchWidget<CasioW738H>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
