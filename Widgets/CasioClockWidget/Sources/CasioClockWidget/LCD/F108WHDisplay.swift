import SwiftUI

/// The F-108WH's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, PM, weekday and day of month, a large H:MM and seconds, in slanted 7-segment
/// characters. Measured on a front-on product image of the F-108WHC-2A, in that face's canvas
/// coordinates; `canvasOrigin` is where its 307.5 × 202.5 glass sits on that canvas (`placed(in:)`).
/// The marks are shown on, as in the image.
struct F108WHDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 307.5, height: 202.5)
    /// The glass's top-left corner on the F-108WH canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 192, y: 288)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark(arcs: 3).fill(style.ink).frame(width: 31, height: 15).offset(x: 215.5, y: 309.5)
            BellMark().fill(style.ink).frame(width: 17, height: 21).offset(x: 259, y: 307.5)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 206, y: 358, width: 40.5, height: 14), color: style.ink, bold: 0.8)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the F-108WH image (canvas points).
    static let weekday = LCDRun(glyph: 58.5, edge: .trailing(390), baseline: 360.5, xScale: 0.82, tracking: 2.9)
    static let day = LCDRun(glyph: 59, edge: .trailing(491), baseline: 360.5, xScale: 0.82, tracking: 0.6, width: 120)
    static let time = LCDRun(
        glyph: 96, edge: .trailing(418), baseline: 474.5, xScale: 0.70, tracking: -3.4, colonGap: 2.9)
    static let seconds = LCDRun(glyph: 68, edge: .trailing(496), baseline: 474, xScale: 0.68, tracking: 0.4)
    static let runs = [weekday, day, time, seconds]
}
