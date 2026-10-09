import SwiftUI

/// The A178W's display (named after the watch; its module number is not checked here): a
/// three-letter weekday and month-day on top, P for PM, a large H:MM and seconds, and SNZ / ALM /
/// SIG below, in upright 7-segment characters. Measured on a front-on product image of the
/// A178WA-1A, in that face's canvas coordinates; `canvasOrigin` is where its 329.5 × 312 glass sits
/// on that canvas (`placed(in:)`). SNZ / ALM / SIG are shown on, as in the image.
struct A178WDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 329.5, height: 312)
    /// The glass's top-left corner on the A178W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 129.5, y: 156)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.month, .day], from: context.date)
        inGlass(style: style) {
            LCDText(
                text: DisplayParts.weekday3(for: context.date, calendar: context.calendar), font: style.letters,
                run: Self.weekday, style: style)
            LCDText(
                text: DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), font: style.digits,
                run: Self.date.trailing(Self.monthTrailing), style: style)
            Rectangle().fill(style.ink).frame(width: 10, height: 6).offset(x: 361, y: 206)
            LCDText(
                text: DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), font: style.digits,
                run: Self.date, style: style)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.saira)
                    .placed(in: CGRect(x: 148, y: 297, width: 14, height: 25), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
            label("SNZ", CGRect(x: 164.5, y: 435.5, width: 70.5, height: 17))
            label("ALM", CGRect(x: 260.5, y: 434.5, width: 71, height: 16.5))
            label("SIG", CGRect(x: 364.5, y: 434, width: 63.5, height: 15.5))
        }
    }

    private func label(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.6)
    }

    // Measured on the A178W image (canvas points).
    static let weekday = LCDRun(
        glyph: 68.5, edge: .leading(166.3), baseline: 245.5, xScale: 0.59, tracking: 18.7, width: 300)
    /// Anchored at the day; the month uses `.trailing(monthTrailing)`.
    static let date = LCDRun(
        glyph: 68.5, edge: .trailing(446.9), baseline: 243.5, xScale: 0.586, tracking: 4.7, width: 120)
    static let time = LCDRun(
        glyph: 144, edge: .trailing(359.9), baseline: 417, xScale: 0.507, tracking: -9, colonGap: -3.1)
    static let seconds = LCDRun(glyph: 109.5, edge: .trailing(453.4), baseline: 414.5, xScale: 0.479, tracking: 2.5)
    static let runs = [weekday, date, time, seconds]
    static let monthTrailing: CGFloat = 359.9
}
