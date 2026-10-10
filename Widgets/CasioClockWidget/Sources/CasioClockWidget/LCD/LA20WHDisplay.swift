import SwiftUI

/// The LA-20WH's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, PM, weekday and day of month, a large H:MM and seconds, in slanted 7-segment
/// characters on an inverted (negative) display. Measured on a front-on product image of the
/// LA-20WH-1B, in that face's canvas coordinates; `canvasOrigin` is where its 237.5 × 169 glass sits
/// on that canvas (`placed(in:)`). The marks are shown on, as in the image.
struct LA20WHDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 237.5, height: 169)
    /// The glass's top-left corner on the LA-20WH canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 154, y: 167)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark(arcs: 3).fill(style.ink).frame(width: 22.5, height: 11).offset(x: 178, y: 190)
            BellMark().fill(style.ink).frame(width: 11.5, height: 14.5).offset(x: 211, y: 189)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 170, y: 224, width: 30.5, height: 11), color: style.ink, bold: 0.6)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the LA-20WH image (canvas points).
    static let weekday = LCDRun(glyph: 37.5, edge: .trailing(318.5), baseline: 224, xScale: 0.91, tracking: 6.7)
    static let day = LCDRun(glyph: 38, edge: .trailing(382), baseline: 224, xScale: 0.86, tracking: 0.3, width: 120)
    static let time = LCDRun(
        glyph: 74, edge: .trailing(328.5), baseline: 314.5, xScale: 0.666, tracking: -1.1, colonGap: 2.3)
    static let seconds = LCDRun(glyph: 52.5, edge: .trailing(382), baseline: 314.5, xScale: 0.593, tracking: 1)
    static let runs = [weekday, day, time, seconds]
}
