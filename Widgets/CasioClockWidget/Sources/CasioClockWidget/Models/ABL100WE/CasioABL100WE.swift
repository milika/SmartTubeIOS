import SwiftUI
import WidgetKit

// The Casio ABL-100WE (ABL-100WE-1A), the Bluetooth step-tracker A168: a steel case, a black plate
// inside a blue and a white line, CASIO and the gold STEP TRACKER, the blue ILLUMINATOR, the LCD
// (ABL100WEDisplay), ADJUST / MODE and LIGHT / SEARCH with red dots, the red WATER WR RESIST, a
// rule and the gold Bluetooth. Laid out on a canvas measured from a front-on product image the
// owner supplied (1200 px, measured only, not shipped): canvas = image − (280, 230).
enum CasioABL100WE: CasioModel {
    static let kind = "CasioABL100WE"
    static let displayName = "Casio ABL-100WE"
    static let summary = "A live digital clock in the style of the Casio ABL-100WE step tracker. Tap it for the light."

    static let canvas = CGSize(width: 640, height: 700)
    /// Zoomed in on the plate: its top and bottom edges just inside the widget (a hairline of
    /// steel), its sides cropped by 20 pt (the side labels stay clear of the edge).
    static let widgetArea = CGRect(x: 82.75, y: 118, width: 450, height: 450)

    /// Polished steel (as the A168W).
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.88), Color(white: 0.62), Color(white: 0.80), Color(white: 0.56), Color(white: 0.74)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { ABL100WEFace(context: context) }

    /// The step bar fills toward 10,000 steps from the Health app (CasioSteps).
    static let usesSteps = true

    // Colours sampled from the image.
    static let plate = Color(red: 0.06, green: 0.075, blue: 0.105)
    static let blue = Color(red: 0.03, green: 0.37, blue: 0.59)
    static let blueprint = Color(red: 0.02, green: 0.33, blue: 0.55)
    static let line = Color(red: 0.86, green: 0.89, blue: 0.89)
    static let rule = Color(red: 0.66, green: 0.67, blue: 0.70)
    static let printWhite = Color(red: 0.90, green: 0.91, blue: 0.94)
    static let gold = Color(red: 0.79, green: 0.65, blue: 0.46)
    static let red = Color(red: 0.70, green: 0.30, blue: 0.32)

    /// Upright 7-segment digits on pale grey glass.
    static let lcd = LCDStyle(
        digits: .dseg7("Bold"), letters: .dseg7("Bold"), glass: Color(red: 0.64, green: 0.655, blue: 0.61),
        ink: Color(red: 0.08, green: 0.09, blue: 0.07), shadow: LCDShadow(edgeOpacity: 0))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("ABL-100WE", as: .systemSmall) {
    CasioWatchWidget<CasioABL100WE>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
