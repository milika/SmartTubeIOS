import SwiftUI

/// The W-738H's display (its Casio module number is not checked here, so it is named after the
/// watch): VIB, weekday and month-date on top, P for PM, a very large H:MM, signal and alarm marks
/// over the seconds, and printed divider lines - an inverted (negative) LCD in the owner's model.
/// Measured on a front-on image of the W-738H, in that face's canvas coordinates; `canvasOrigin` is
/// where its 333.5 × 248 glass sits on that canvas (`placed(in:)`). VIB and the marks are shown on,
/// as in the image.
struct W738HDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 333.5, height: 248)
    /// The glass's top-left corner on the W-738H canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 152.5, y: 204)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            // Printed lines: under VIB, the row divider and the bottom line.
            line(x: 155, y: 241.5, width: 77)
            line(x: 155, y: 269.5, width: 77)
            line(x: 152.5, y: 299.25, width: 333.5)
            line(x: 152.5, y: 426, width: 333.5)
            InkText(text: "VIB", font: CaseFont.saira)
                .placed(in: CGRect(x: 176.5, y: 223.5, width: 29.5, height: 12), color: style.ink, bold: 0.3)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.saira)
                    .placed(in: CGRect(x: 164, y: 309, width: 13.5, height: 14.5), color: style.ink, bold: 0.6)
            }
            SignalMark().fill(style.ink).frame(width: 27.5, height: 14).offset(x: 411.5, y: 322)
            BellMark().fill(style.ink).frame(width: 20, height: 25.5).offset(x: 452, y: 316)
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            // Month, a narrow printed dash, day (the dash isn't a full digit cell on this display).
            let date = context.calendar.dateComponents([.day, .month], from: context.date)
            LCDText(
                text: DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), font: style.digits,
                run: Self.date, style: style)
            Rectangle().fill(style.ink).frame(width: 9, height: 5).offset(x: 401, y: 257)
            LCDText(
                text: DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), font: style.digits,
                run: Self.date.trailing(472.5), style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    private func line(x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        Rectangle().fill(style.ink).frame(width: width, height: 2).offset(x: x, y: y)
    }

    // Measured on the W-738H image (canvas points).
    static let weekday = LCDRun(glyph: 53, edge: .leading(257), baseline: 286, xScale: 0.71, tracking: 9)
    static let date = LCDRun(glyph: 53, edge: .trailing(399), baseline: 286, xScale: 0.66)
    static let time = LCDRun(glyph: 92, edge: .trailing(392.5), baseline: 414, xScale: 0.70, colonGap: 16)
    static let seconds = LCDRun(glyph: 63.5, edge: .trailing(473.5), baseline: 414, xScale: 0.70)
    static let runs = [weekday, date, time, seconds]
}
