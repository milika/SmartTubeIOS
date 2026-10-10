import SwiftUI
import WidgetKit

// The Casio W-800H in navy (W-800H-2AV): navy resin with ILLUMINATOR moulded above the face, a black
// face with a white cut-corner line, white print, and the W800HDisplay with the year. Laid out on a
// canvas measured from a front-on product image supplied by the owner (measured only):
// canvas = image (1000 px) − (180, 160).
enum CasioW800H: CasioModel {
    static let kind = "CasioW800H"
    static let displayName = "Casio W-800H"
    static let summary = "A live digital clock in the style of the navy Casio W-800H. Tap it for the light."

    static let canvas = CGSize(width: 580, height: 580)
    /// The face, its bezel and the moulded ILLUMINATOR above it.
    static let widgetArea = CGRect(x: 45, y: 58, width: 490, height: 490)

    /// Navy resin.
    static let caseBackground = Color(red: 0.25, green: 0.29, blue: 0.39)

    static func face(_ context: CasioFaceContext) -> some View { W800HFace(context: context) }

    // Colours sampled from the image.
    static let resinLight = Color(red: 0.31, green: 0.34, blue: 0.45)
    static let bezel = Color(red: 0.19, green: 0.23, blue: 0.32)
    static let engraved = Color(red: 0.13, green: 0.16, blue: 0.24)
    static let plate = Color(white: 0.04)
    static let plateEdge = Color(white: 0.30)
    static let printWhite = Color(white: 0.91)

    /// Upright 7-segment digits and letters on pale grey glass.
    static let lcd = LCDStyle(
        digits: .casio("W800H"), letters: .dseg7("Bold"),
        glass: Color(red: 0.66, green: 0.68, blue: 0.62), ink: Color(white: 0.09))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("W-800H", as: .systemSmall) {
    CasioWatchWidget<CasioW800H>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
