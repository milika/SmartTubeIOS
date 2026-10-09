import SwiftUI

/// The F-105W's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, PM, weekday and day of month, a large H:MM and seconds, in upright 7-segment
/// characters. Measured on a front-on product image of the F-105W-1A, in that face's canvas
/// coordinates; `canvasOrigin` is where its 387 × 193.5 glass sits on that canvas (`placed(in:)`).
/// The marks are shown on, as in the image.
struct F105WDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 387, height: 193.5)
    /// The glass's top-left corner on the F-105W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 128, y: 218)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark().fill(style.ink).frame(width: 39.5, height: 16).offset(x: 145.5, y: 240.5)
            BellMark().fill(style.ink).frame(width: 18.5, height: 22).offset(x: 200.5, y: 238)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 145, y: 268.5, width: 37.5, height: 19), color: style.ink, bold: 0.6)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the F-105W image (canvas points).
    static let weekday = LCDRun(glyph: 42, edge: .leading(252.5), baseline: 281.5, xScale: 1.05, tracking: 4.8)
    static let day = LCDRun(glyph: 48, edge: .trailing(491), baseline: 287, xScale: 1.02, tracking: 0.5, width: 120)
    static let time = LCDRun(
        glyph: 91, edge: .trailing(398), baseline: 394.5, xScale: 0.86, tracking: 0.1, colonGap: 0.3)
    static let seconds = LCDRun(glyph: 68, edge: .trailing(490.5), baseline: 394, xScale: 0.84, tracking: -1.6)
    static let runs = [weekday, day, time, seconds]
}
