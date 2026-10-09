import SwiftUI

/// The W-86's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, 24H (PM on a 12-hour clock), weekday and day of month on top, a large italic H:MM
/// and seconds below. Measured on a front-on photo of a W-86, in that face's canvas coordinates;
/// `canvasOrigin` is where its 536.5 × 255 glass sits on that canvas (`placed(in:)`). The marks are
/// shown on, as in the photo.
struct W86Display: LCDModuleDisplay {
    static let glass = CGSize(width: 536.5, height: 255)
    /// The glass's top-left corner on the W-86 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 88, y: 200)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark().fill(style.ink).frame(width: 56, height: 20).offset(x: 129, y: 219.5)
            BellMark().fill(style.ink).frame(width: 26, height: 29.5).offset(x: 204.5, y: 214.5)
            if let marker = parts.marker {
                InkText(text: marker, font: CaseFont.michroma)
                    .placed(
                        in: CGRect(x: 187.5, y: 261, width: marker == "24H" ? 57 : 38, height: 20), color: style.ink,
                        bold: 0.6)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the W-86 photo (canvas points).
    static let weekday = LCDRun(glyph: 55, edge: .leading(329.5), baseline: 278, xScale: 1, tracking: 15.5)
    static let day = LCDRun(glyph: 55, edge: .trailing(591), baseline: 278, xScale: 1.14, tracking: 5, width: 160)
    static let time = LCDRun(glyph: 116, edge: .trailing(482), baseline: 421, xScale: 0.9, tracking: 6.1, colonGap: 4)
    static let seconds = LCDRun(glyph: 84, edge: .trailing(614), baseline: 420.5, xScale: 0.86, tracking: 5.4)
    static let runs = [weekday, day, time, seconds]
}
