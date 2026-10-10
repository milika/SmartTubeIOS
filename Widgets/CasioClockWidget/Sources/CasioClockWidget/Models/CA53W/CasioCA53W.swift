import SwiftUI
import WidgetKit

// The Casio CA-53W calculator watch: a display section (CASIO, blue WATER RESIST / ALARM CHRONO, a
// gold WR, an upright 7-segment LCD) above a black keypad of 16 rubber keys with white digits, red
// operators and tan function labels. Laid out on a canvas measured from a front-on photo
// (Wikimedia Commons, `Casio CA-53W, 1.jpg`, by Morn, CC BY-SA 4.0; levelled by 0.8°):
// canvas = photo at 960 px wide − (160, 290). Printed labels fill the ink boxes measured on the
// photo (InkText). The real watch has no light; the widget keeps the package's tap-for-light.
enum CasioCA53W: CasioModel {
    static let kind = "CasioCA53W"
    static let displayName = "Casio CA-53W"
    static let summary = "A live digital clock in the style of the Casio CA-53W calculator watch. Tap it for the light."

    /// The face is taller than wide, so the square widget shows case on both sides: the canvas is
    /// the photo's plus `sidePad` of case left and right (the face is drawn shifted by it).
    static let sidePad: CGFloat = 40
    static let canvas = CGSize(width: 640 + 2 * sidePad, height: 740)
    /// The whole face, display and keypad.
    static let widgetArea = CGRect(x: 10, y: 12, width: 700, height: 700)

    static let caseBackground = Color(white: 0.12)

    static func face(_ context: CasioFaceContext) -> some View { CA53WFace(context: context).offset(x: sidePad) }

    // Colours sampled from the photo, white-balanced on the CASIO print.
    static let plate = Color(white: 0.11)
    static let keypadPlate = Color(white: 0.10)
    static let panelEdge = Color(white: 0.19)
    static let printWhite = Color(white: 0.92)
    static let lineWhite = Color(white: 0.88)
    static let blue = Color(red: 0.33, green: 0.62, blue: 0.74)
    static let gold = Color(red: 0.82, green: 0.65, blue: 0.18)
    static let tan = Color(red: 0.58, green: 0.55, blue: 0.44)
    static let key = Color(white: 0.30)
    static let bar = Color(red: 0.39, green: 0.43, blue: 0.45)
    /// The operator signs are a dull brick red; lifted a little so they read at widget size.
    static let red = Color(red: 0.62, green: 0.27, blue: 0.18)

    /// Upright 7-segment digits and letters (DSEG7 Bold, squeezed to the module's narrower cells) on
    /// pale grey glass.
    static let lcd = LCDStyle(
        digits: .casio("CA53W"), letters: .dseg7("Bold"),
        glass: Color(red: 0.78, green: 0.79, blue: 0.73), ink: Color(red: 0.19, green: 0.23, blue: 0.23))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("CA-53W", as: .systemSmall) {
    CasioWatchWidget<CasioCA53W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
