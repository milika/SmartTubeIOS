import SwiftUI

// The Casio G-Shock GMW-B5000D: a brushed-steel octagon bezel (PROTECTION / G-SHOCK engraved)
// around a black face with a brick pattern and a blue-grey LCD with a dot-matrix date. Laid out
// on a canvas measured from a front-on photo (Wikimedia Commons,
// Wikipedia-Casio-G-Shock-Edelstahl-800.jpg): canvas = photo − (85, 160). Printed text uses the
// package's free fonts (Michroma, Saira Medium); the date's dots are drawn as shapes.
enum CasioGMWB5000: CasioModel {
    static let kind = "CasioGMWB5000"
    static let displayName = "G-Shock GMW-B5000"
    static let summary = "A live digital clock in the style of the steel G-Shock GMW-B5000. Tap it for the light."

    /// The widget shows the black face inside the steel bezel (owner: no big bezel). The face is
    /// wider than tall, so the case is extended until it is square (elements keep their measured
    /// size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 68
    static let canvas = CGSize(width: 630, height: 560 + caseExtension)
    /// The black face plate (its rounded corners match the widget's).
    static let widgetArea = CGRect(x: 81, y: 87, width: 451, height: 451)

    /// Behind the face: the plate's black.
    static let caseBackground = Color(white: 0.09)

    static func face(_ context: CasioFaceContext) -> some View { GMWB5000Face(context: context) }

    // Colours sampled from the photo, scaled so the white print is neutral.
    static let steel = LinearGradient(
        colors: [Color(white: 0.90), Color(white: 0.80), Color(white: 0.86), Color(white: 0.74)],
        startPoint: .top, endPoint: .bottom)
    static let steelEdge = Color(white: 0.55)
    static let engraveShadow = Color(white: 0.42)
    static let plate = Color(white: 0.09)
    static let bevel = Color(white: 0.93)
    static let frameLine = Color(white: 0.42)
    static let brick = Color(white: 0.27)
    static let printWhite = Color(white: 0.92)
    static let printGrey = Color(white: 0.62)
    /// The button and feature labels are printed light grey.
    static let labelGrey = Color(white: 0.76)

    /// Blue-grey glass and navy ink (the photo's), DSEG digits; the LED lights the whole display.
    static let lcd = LCDStyle(
        glass: Color(red: 0.47, green: 0.71, blue: 0.89), ink: Color(red: 0.06, green: 0.17, blue: 0.57),
        backlight: Color(red: 0.86, green: 0.95, blue: 1.0), backlightFalloff: [0.85, 0.85, 0.85])
    static let surround = Color(white: 0.22)
}
