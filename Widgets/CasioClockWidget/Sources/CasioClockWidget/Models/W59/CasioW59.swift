import SwiftUI
import WidgetKit

// The Casio W-59: black resin, a blue band and two white octagon lines around a module-590
// LCD (24H, weekday, date, H:MM, seconds - Module590Display), gold and red print. Laid out on a
// canvas measured from a front-on photo (Wikimedia Commons, Casio W-59 digital watch.jpg, public
// domain): canvas = (photo − 120) / 2. Printed labels fill the ink boxes measured on the photo
// (InkText).
enum CasioW59: CasioModel {
    static let kind = "CasioW59"
    static let displayName = "Casio W-59"
    static let summary = "A live digital clock in the style of the Casio W-59. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (elements keep
    /// their measured size; the lines grow, the LCD window grows by half and the print below moves).
    static let caseExtension: CGFloat = 56.5
    static let canvas = CGSize(width: 540, height: 520 + caseExtension)
    /// The black face around the outer white line.
    static let widgetArea = CGRect(x: 36, y: 24, width: 470, height: 470)

    /// Black resin.
    static let caseBackground = Color(white: 0.11)

    static func face(_ context: CasioFaceContext) -> some View { W59Face(context: context) }

    // Colours sampled from the photo, white-balanced on the CASIO print.
    static let plate = Color(white: 0.13)
    static let printWhite = Color(white: 0.94)
    static let labelWhite = Color(white: 0.84)
    static let line = Color(white: 0.85)
    static let gold = Color(red: 0.70, green: 0.60, blue: 0.38)
    static let blue = Color(red: 0.31, green: 0.58, blue: 0.91)
    static let red = Color(red: 0.86, green: 0.34, blue: 0.28)

    /// Module 590's display (Module590Display) on slightly warmer glass.
    static let lcd = LCDStyle(digits: .casio("W59"), glass: Color(red: 0.70, green: 0.68, blue: 0.60))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("W-59", as: .systemSmall) {
    CasioWatchWidget<CasioW59>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
