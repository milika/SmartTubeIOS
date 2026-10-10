import SwiftUI
import WidgetKit

// The Casio F-108WH, navy and gold (F-108WHC-2A): navy resin with gold ILLUMINATOR and WATER
// RESIST, a gold octagon line around a black face, CASIO, START/STOP and ALARM CHRONO on a blue
// panel, the LCD in a black frame (F108WHDisplay), MODE, LIGHT and the WR badge. Laid out on a
// canvas measured from a front-on product image the owner supplied (measured only, not shipped):
// image px = (270, 240) + 0.75 × canvas.
enum CasioF108WH: CasioModel {
    static let kind = "CasioF108WH"
    static let displayName = "Casio F-108WH"
    static let summary = "A live digital clock in the style of the Casio F-108WH. Tap it for the light."

    static let canvas = CGSize(width: 720, height: 740)
    /// The face from the case's top edge to its bottom, centred on the gold line.
    static let widgetArea = CGRect(x: 86, y: 116, width: 516, height: 516)

    /// Navy resin.
    static let caseBackground = Color(red: 0.20, green: 0.20, blue: 0.32)

    static func face(_ context: CasioFaceContext) -> some View { F108WHFace(context: context) }

    // Colours sampled from the image.
    static let resin = Color(red: 0.20, green: 0.20, blue: 0.32)
    static let guardBlock = Color(red: 0.13, green: 0.14, blue: 0.26)
    static let screw = Color(red: 0.11, green: 0.12, blue: 0.22)
    static let chrome = Color(white: 0.85)
    static let gold = Color(red: 0.61, green: 0.58, blue: 0.33)
    static let goldShade = Color(red: 0.27, green: 0.26, blue: 0.22)
    static let goldPrint = Color(red: 0.71, green: 0.67, blue: 0.44)
    static let face = Color(red: 0.03, green: 0.04, blue: 0.08)
    static let panel = Color(red: 0.06, green: 0.09, blue: 0.29)
    static let rim = Color(red: 0.53, green: 0.54, blue: 0.52)
    static let printWhite = Color(red: 0.84, green: 0.84, blue: 0.85)
    static let printGrey = Color(red: 0.62, green: 0.63, blue: 0.66)

    /// Slanted 7-segment digits on pale grey-green glass.
    static let lcd = LCDStyle(
        digits: .casio("F108WH"), letters: .dseg7("BoldItalic"),
        glass: Color(red: 0.64, green: 0.66, blue: 0.60), ink: Color(red: 0.07, green: 0.08, blue: 0.07))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("F-108WH", as: .systemSmall) {
    CasioWatchWidget<CasioF108WH>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
