import SwiftUI
import WidgetKit

// The Casio LA680W: a small chrome octagon with a black face, a grey line around it, the LCD in a
// grey-outlined window (LA680WDisplay), START / MODE / LIGHT, WATER [WR] RESIST and ILLUMINATOR.
// Laid out on a canvas measured from a front-on product image (LA680WA-1, 1200 px, supplied by the
// owner, measured only): image px = (360, 300) + 0.75 × canvas, before the case extension.
enum CasioLA680W: CasioModel {
    static let kind = "CasioLA680W"
    static let displayName = "Casio LA680W"
    static let summary = "A live digital clock in the style of the Casio LA680W. Tap it for the light."

    /// The face is wider than tall; the case is extended until the widget is square (elements keep
    /// their measured size; the LCD window grows by half and the groups spread apart).
    static let caseExtension: CGFloat = 55
    static let canvas = CGSize(width: 640, height: 640 + caseExtension)
    /// The face and a strip of the chrome case around it.
    static let widgetArea = CGRect(x: 40, y: 110, width: 544, height: 544)

    /// Polished steel.
    static let caseBackground = LinearGradient(
        colors: [Color(white: 0.90), Color(white: 0.70), Color(white: 0.84), Color(white: 0.64), Color(white: 0.76)],
        startPoint: .top, endPoint: .bottom)

    static func face(_ context: CasioFaceContext) -> some View { LA680WFace(context: context) }

    // Colours sampled from the image.
    static let rim = Color(red: 0.094, green: 0.094, blue: 0.102)
    static let line = Color(red: 0.44, green: 0.47, blue: 0.49)
    static let plate = Color(red: 0.063, green: 0.063, blue: 0.075)
    static let windowOutline = Color(red: 0.48, green: 0.51, blue: 0.53)
    static let printWhite = Color(red: 0.74, green: 0.76, blue: 0.77)
    static let printGrey = Color(red: 0.47, green: 0.51, blue: 0.52)

    /// Upright 7-segment digits on pale grey glass; the EL panel glows blue-green.
    static let lcd = LCDStyle(
        digits: .dseg7("Bold"), letters: .dseg7("Bold"), glass: Color(red: 0.62, green: 0.62, blue: 0.58),
        ink: Color(white: 0.08),
        backlight: Color(red: 0.55, green: 0.95, blue: 0.92), backlightFalloff: [1, 1, 0.95])
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("LA680W", as: .systemSmall) {
    CasioWatchWidget<CasioLA680W>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
