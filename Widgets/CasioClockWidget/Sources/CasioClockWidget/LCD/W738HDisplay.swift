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
    private static let canvasOrigin = CGPoint(x: 152.5, y: 204)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
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
            LCDText(
                text: DisplayParts.sevenSegmentLetters(parts.weekday), font: style.letters, glyph: Self.topGlyph,
                edge: .leading(Self.weekdayLeading), baseline: Self.topBaseline, tracking: Self.weekdayTracking,
                xScale: Self.weekdayScale, style: style)
            // Month, a narrow printed dash, day (the dash isn't a full digit cell on this display).
            let date = context.calendar.dateComponents([.day, .month], from: context.date)
            LCDText(
                text: DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), font: style.digits,
                glyph: Self.topGlyph, edge: .trailing(Self.monthTrailing), baseline: Self.topBaseline,
                xScale: Self.dateScale, style: style)
            Rectangle().fill(style.ink).frame(width: 9, height: 5).offset(x: 401, y: 257)
            LCDText(
                text: DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), font: style.digits,
                glyph: Self.topGlyph, edge: .trailing(Self.dateTrailing), baseline: Self.topBaseline,
                xScale: Self.dateScale, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: Self.timeGlyph, trailing: Self.timeTrailing,
                baseline: Self.timeBaseline, xScale: Self.timeScale, colonGap: Self.colonGap, style: style)
            LiveSeconds(
                context: context, glyph: Self.secondsGlyph, trailing: Self.secondsTrailing,
                baseline: Self.secondsBaseline, xScale: Self.secondsScale, style: style)
        }
        .lcdSegmentShadow(style)
        .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    private func line(x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        Rectangle().fill(style.ink).frame(width: width, height: 2).offset(x: x, y: y)
    }

    // Measured on the W-738H image (canvas points).
    static let topGlyph: CGFloat = 53
    static let topBaseline: CGFloat = 286
    static let weekdayLeading: CGFloat = 257
    static let weekdayTracking: CGFloat = 9
    static let weekdayScale: CGFloat = 0.71
    static let dateTrailing: CGFloat = 472.5
    static let monthTrailing: CGFloat = 399
    static let dateScale: CGFloat = 0.66
    static let timeGlyph: CGFloat = 92
    static let timeTrailing: CGFloat = 392.5
    static let timeBaseline: CGFloat = 414
    static let timeScale: CGFloat = 0.70
    static let colonGap: CGFloat = 16
    static let secondsGlyph: CGFloat = 63.5
    static let secondsTrailing: CGFloat = 473.5
    static let secondsBaseline: CGFloat = 414
    static let secondsScale: CGFloat = 0.70
}
