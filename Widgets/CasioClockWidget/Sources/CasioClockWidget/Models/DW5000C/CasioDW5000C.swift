import SwiftUI

// The Casio G-Shock DW-5000C (1983), the first G-Shock: a black resin case, a black face with a
// red octagon line and a brick pattern, gold and teal print and a beige LCD in a silver frame.
// Laid out on a canvas measured from a front-on photo (Wikimedia Commons, DW-5000.jpg, 1823 px;
// canvas = photo at 960 px − (170, 240)). Printed labels are drawn as glyph outlines filling the
// ink boxes measured on the photo (InkText), in the package's free fonts.
enum CasioDW5000C: CasioModel {
    static let kind = "CasioDW5000C"
    static let displayName = "G-Shock DW-5000C"
    static let summary = "A live digital clock in the style of the first G-Shock, the DW-5000C. Tap it for the light."

    /// The widget shows the face inside the bezel. It is wider than tall, so the case is extended
    /// until it is square (elements keep their measured size; the LCD window grows by half and the
    /// groups spread apart).
    static let caseExtension: CGFloat = 60
    static let canvas = CGSize(width: 620, height: 500 + caseExtension)
    static let widgetArea = CGRect(x: 61, y: 35, width: 500, height: 500)
    static let fonts = [
        lcd.digits.postScriptName, lcd.letters.postScriptName, CaseFont.michroma, CaseFont.saira,
        CaseFont.archivoBlack,
    ]

    /// Black resin.
    static let caseBackground = Color(red: 0.20, green: 0.19, blue: 0.17)

    static func face(_ context: CasioFaceContext) -> some View { DW5000CFace(context: context) }

    // Colours sampled from the photo, scaled so the white print is neutral (the photo is warm).
    static let recess = Color(white: 0.05)
    static let red = Color(red: 0.66, green: 0.18, blue: 0.16)
    static let mortar = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let brick = Color(white: 0.09)
    static let printWhite = Color(white: 0.92)
    static let labelWhite = Color(white: 0.84)
    static let gold = Color(red: 0.74, green: 0.68, blue: 0.43)
    static let teal = Color(red: 0.53, green: 0.74, blue: 0.76)
    static let silver = Color(red: 0.95, green: 0.95, blue: 0.93)

    /// Beige glass, dark ink; the bulb lights the display warm yellow from the left.
    static let lcd = LCDStyle(
        glass: Color(red: 0.77, green: 0.73, blue: 0.57), ink: Color(red: 0.09, green: 0.13, blue: 0.13),
        backlight: Color(red: 1.0, green: 0.86, blue: 0.45), backlightFalloff: [0.95, 0.75, 0.5])
}
