import SwiftUI
import WidgetKit

// The Casio DBC-32 Databank: a black resin case with CASIO / Multi Lingual DATA BANK / 10 Year
// Battery above a slate-blue plate and the LCD, a silver ILLUMINATOR badge, and a grey keypad of 16
// keys with white print and red rules. Laid out on a canvas measured from a front-on photo
// (Wikimedia Commons, `Casio DBC-32-1AES mit Resin Armband.jpg`, by Lebensanalyst Biogr. Herr
// Binjansen, CC BY-SA 4.0; upright by its EXIF orientation, levelled by 0.8°): canvas = (photo − (560,
// 800)) / 3. Printed labels fill the ink boxes measured on the photo (InkText). The photo's lens
// bows the keypad's rules a little; they are drawn straight, at the middle keys' height.
enum CasioDBC32: CasioModel {
    static let kind = "CasioDBC32"
    static let displayName = "Casio DBC-32"
    static let summary = "A live digital clock in the style of the Casio DBC-32 Databank. Tap it for the light."

    /// The face is taller than wide, so the square widget shows case on both sides: the canvas is
    /// the photo's plus `sidePad` of case left and right (the face is drawn shifted by it).
    static let sidePad: CGFloat = 55
    static let canvas = CGSize(width: 640 + 2 * sidePad, height: 820)
    /// The whole face, display and keypad.
    static let widgetArea = CGRect(x: 0, y: 18, width: 750, height: 750)

    static let caseBackground = Color(red: 0.09, green: 0.10, blue: 0.12)

    static func face(_ context: CasioFaceContext) -> some View { DBC32Face(context: context).offset(x: sidePad) }

    // Colours sampled from the photo, white-balanced on the paper behind the watch.
    static let resin = Color(red: 0.09, green: 0.10, blue: 0.12)
    /// The light catching the case's edges, so its outline shows on the widget's case-coloured ground.
    static let caseEdge = Color(white: 0.22)
    static let button = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let rimEdge = Color(white: 0.30)
    static let band = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let plate = Color(red: 0.31, green: 0.35, blue: 0.40)
    static let lcdFrame = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let print = Color(red: 0.68, green: 0.71, blue: 0.75)
    static let badgeBar = Color(white: 0.24)
    static let silver = Color(red: 0.70, green: 0.72, blue: 0.70)
    static let keypad = Color(red: 0.40, green: 0.39, blue: 0.38)
    static let keyEdge = Color(white: 0.17)
    static let keyLip = Color(white: 0.24)
    static let keyPrint = Color(red: 0.90, green: 0.90, blue: 0.91)
    static let red = Color(red: 0.62, green: 0.42, blue: 0.40)

    /// Slanted 7-segment digits on yellow-green glass.
    static let lcd = LCDStyle(
        digits: .casio("DBC32"), letters: .dseg7("BoldItalic"),
        glass: Color(red: 0.64, green: 0.65, blue: 0.56), ink: Color(red: 0.10, green: 0.11, blue: 0.15),
        shadow: LCDShadow(edgeOpacity: 0))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("DBC-32", as: .systemSmall) {
    CasioWatchWidget<CasioDBC32>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
