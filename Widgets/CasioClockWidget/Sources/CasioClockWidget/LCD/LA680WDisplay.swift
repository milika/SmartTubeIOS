import SwiftUI

/// The LA680W's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, weekday and day of month on top, PM on a 12-hour clock, a large H:MM and seconds.
/// Measured on a front-on product image of the LA680WA-1, in that face's canvas coordinates;
/// `canvasOrigin` is where its 300.5 × 211.5 glass sits on that canvas (`placed(in:)`). The marks
/// are shown on, as in the image.
struct LA680WDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 300.5, height: 211.5)
    /// The glass's top-left corner on the LA680W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 159.5, y: 248)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark(arcs: 3).fill(style.ink).frame(width: 30.5, height: 13.5).offset(x: 186.5, y: 276.5)
            BellMark().fill(style.ink).frame(width: 16, height: 20.5).offset(x: 229.5, y: 273.5)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 177.5, y: 321, width: 39.5, height: 14), color: style.ink, bold: 0.6)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the LA680W image (canvas points).
    static let weekday = LCDRun(glyph: 49.5, edge: .leading(281), baseline: 320.5, xScale: 0.95, tracking: 4.5)
    static let day = LCDRun(glyph: 50, edge: .trailing(452), baseline: 319, xScale: 0.92, tracking: 0, width: 120)
    static let time = LCDRun(
        glyph: 97, edge: .trailing(380), baseline: 437.5, xScale: 0.725, tracking: -7.5, colonGap: 3.3)
    static let seconds = LCDRun(glyph: 69, edge: .trailing(452), baseline: 437, xScale: 0.62, tracking: 0.5)
    static let runs = [weekday, day, time, seconds]
}
