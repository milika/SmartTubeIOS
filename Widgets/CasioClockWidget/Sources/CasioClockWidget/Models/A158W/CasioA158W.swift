import SwiftUI

// The Casio A158W: the F-91W's LCD module in a chrome metal case with a black face, one
// steel-blue octagon line and a WATER RESIST band. Laid out on a canvas measured from a
// front-on photo (Wikimedia Commons, A158W.jpg): canvas = (photo − (110, 175)) × 1.5.
// Printed text uses the F-91W's free look-alike fonts (Michroma, Saira Medium, Saira Expanded).
enum CasioA158W: CasioModel {
    static let kind = "CasioA158W"
    static let displayName = "Casio A158W"
    static let summary = "A live digital clock in the style of the Casio A158W. Tap it for the light."

    /// Like the F-91W, the face is wider than tall; the case is extended to fill the square widget
    /// (elements keep their measured size; the LCD window grows by half and the groups spread).
    static let caseExtension: CGFloat = 91.5
    static let canvas = CGSize(width: 600, height: 600)
    /// The face plate plus a strip of the chrome case around it.
    static let widgetArea = CGRect(x: 19, y: 8.5, width: 572.5, height: 572.5)
    static let fonts = [
        lcd.digits.postScriptName, lcd.letters.postScriptName, CaseFont.michroma, CaseFont.saira,
        CaseFont.sairaExpanded,
    ]

    /// Polished steel.
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.88), Color(white: 0.62), Color(white: 0.80), Color(white: 0.56), Color(white: 0.74)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { A158WFace(context: context) }

    // Colours sampled from the photo, scaled so the white print is neutral (the photo is dark).
    static let plate = Color(white: 0.06)
    static let blue = Color(red: 0.21, green: 0.37, blue: 0.46)
    static let band = Color(red: 0.17, green: 0.24, blue: 0.30)
    static let gold = Color(red: 0.74, green: 0.68, blue: 0.49)
    static let paleGold = Color(red: 0.65, green: 0.62, blue: 0.49)
    static let printWhite = Color(white: 0.94)
    static let line = Color(white: 0.80)
    /// The WR is printed in a very dark maroon; lifted a little so it reads at widget size.
    static let maroon = Color(red: 0.36, green: 0.12, blue: 0.14)
    static let marker = Color(red: 0.55, green: 0.12, blue: 0.14)

    /// The same LCD module (593) as the F-91W: same glass, ink and layout (Module593Display).
    static let lcd = LCDStyle()
}
