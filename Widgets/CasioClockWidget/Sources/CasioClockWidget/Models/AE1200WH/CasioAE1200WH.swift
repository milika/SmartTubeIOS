import SwiftUI
import WidgetKit

// The Casio AE-1200WH ("Royale"), silver version (AE-1200WH-1CV): a silver octagonal case with
// WORLD TIME and ILLUMINATOR on its bands, a dark bezel and plate, an LCD dial, MUTE / ALM SIG and
// world-map windows, and the main time window. Laid out on a canvas measured from a front-on
// product image the owner supplied (measured only, not shipped): canvas = image − (200, 160).
// Printed labels fill the ink boxes measured on the image (InkText).
enum CasioAE1200WH: CasioModel {
    static let kind = "CasioAE1200WH"
    static let displayName = "Casio AE-1200WH"
    static let summary =
        "A live digital clock in the style of the Casio AE-1200WH world-time watch. Tap it for the light."

    static let canvas = CGSize(width: 680, height: 680)
    /// The bezel with a strip of the steel case above and below (as the A158W); WORLD TIME and
    /// ILLUMINATOR on the case are left out.
    static let widgetArea = CGRect(x: 70, y: 91.5, width: 520, height: 520)

    static let caseBackground = Color(red: 0.12, green: 0.13, blue: 0.15)

    static func face(_ context: CasioFaceContext) -> some View { AE1200WHFace(context: context) }

    // Colours sampled from the image.
    static let strap = Color(red: 0.21, green: 0.22, blue: 0.26)
    static let silver = Color(red: 0.82, green: 0.84, blue: 0.84)
    static let silverSide = Color(red: 0.68, green: 0.70, blue: 0.69)
    static let chrome = Color(white: 0.78)
    static let caseInk = Color(red: 0.09, green: 0.10, blue: 0.11)
    static let bezel = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let bezelSlope = Color(red: 0.08, green: 0.09, blue: 0.12)
    static let plate = Color(red: 0.15, green: 0.155, blue: 0.20)
    static let plateLine = Color(red: 0.44, green: 0.45, blue: 0.47)
    static let dialRing = Color(red: 0.18, green: 0.19, blue: 0.24)
    static let dialHousing = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let windowRim = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let printBright = Color(red: 0.70, green: 0.72, blue: 0.75)
    static let print = Color(red: 0.57, green: 0.58, blue: 0.63)
    static let printSide = Color(red: 0.51, green: 0.52, blue: 0.57)

    /// Slanted segments on pale grey-green glass; the image shows almost no segment shadow.
    static let lcd = LCDStyle(
        digits: .casio("AE1200WH"), letters: .dseg14("BoldItalic"),
        glass: Color(red: 0.64, green: 0.65, blue: 0.60), ink: Color(red: 0.075, green: 0.085, blue: 0.075),
        shadow: LCDShadow(edgeOpacity: 0, segmentOpacity: 0.1))
}

#if !os(watchOS)
// Xcode canvas: tune the widget live (normal and lit).
#Preview("AE-1200WH", as: .systemSmall) {
    CasioWatchWidget<CasioAE1200WH>()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
