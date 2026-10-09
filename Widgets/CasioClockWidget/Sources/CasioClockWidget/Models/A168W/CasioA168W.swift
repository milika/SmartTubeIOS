import SwiftUI
import WidgetKit

// The Casio A168W: a chrome case around a black face with a blue and a white octagon line, the blue
// ElectroLuminescence banner, ILLUMINATOR and WATER [WR] RESIST print, and the module-3298 display
// (Module3298Display) with its EL backlight. Laid out on a canvas measured from Casio's A168WA-1W
// product image (supplied by the owner, measured only): canvas = image (1000 px) − (230, 250).
// Printed labels fill the ink boxes measured on the image (InkText).
enum CasioA168W: CasioModel {
    static let kind = "CasioA168W"
    static let displayName = "Casio A168W"
    static let summary = "A live digital clock in the style of the Casio A168W. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (lines grow,
    /// the LCD window grows by half, the groups below move).
    static let caseExtension: CGFloat = 50
    static let canvas = CGSize(width: 540, height: 500 + caseExtension)
    /// The black face plus a strip of the chrome case.
    static let widgetArea = CGRect(x: 52, y: 41, width: 446, height: 446)

    /// Polished steel (as the A158W).
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.88), Color(white: 0.62), Color(white: 0.80), Color(white: 0.56), Color(white: 0.74)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { A168WFace(context: context) }

    // Colours sampled from the image.
    static let plate = Color(red: 0.11, green: 0.115, blue: 0.13)
    static let blue = Color(red: 0.10, green: 0.33, blue: 0.62)
    static let banner = Color(red: 0.12, green: 0.30, blue: 0.62)
    static let printWhite = Color(white: 0.93)
    static let line = Color(white: 0.75)
    static let gold = Color(red: 0.80, green: 0.74, blue: 0.36)
    static let red = Color(red: 0.84, green: 0.33, blue: 0.24)

    /// Module 3298: italic 7-segment digits and letters on grey-green glass; its EL backlight glows
    /// blue-green.
    static let lcd = LCDStyle(
        letters: .dseg7("BoldItalic"), glass: Color(red: 0.70, green: 0.72, blue: 0.66),
        ink: Color(red: 0.16, green: 0.17, blue: 0.18),
        backlight: Color(red: 0.55, green: 0.95, blue: 0.92), backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("A168W", as: .systemSmall) {
    CasioWatchWidget<CasioA168W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
