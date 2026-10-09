import SwiftUI

/// The W-800H's display (named after the watch; its module number is not checked here): a boxed
/// three-letter weekday, SNZ / ALM / SIG with their bars, P for PM, a large H:MM and seconds, and
/// the year and month-date under a divider, in upright 7-segment characters. Measured on a
/// front-on product image of the W-800H, in that face's canvas coordinates; `canvasOrigin` is where
/// its 287 × 253 glass sits on that canvas (`placed(in:)`). The bars show the alarms on, as in the
/// image.
struct W800HDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 287, height: 253)
    /// The glass's top-left corner on the W-800H canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 147, y: 205)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.year, .month, .day], from: context.date)
        let year = String(format: "%04d", date.year ?? 2000)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).stroke(style.ink, lineWidth: 2.5)
                .frame(width: 143, height: 62).offset(x: 165.25, y: 224.25)
            LCDText(
                text: DisplayParts.weekday3(for: context.date, calendar: context.calendar),
                font: style.letters, glyph: Self.weekdayGlyph, edge: .leading(Self.weekdayLeading),
                baseline: Self.weekdayBaseline, tracking: Self.weekdayTracking, xScale: Self.weekdayScale, style: style)
            label("SNZ", CGRect(x: 325.5, y: 227.5, width: 49.5, height: 12))
            label("ALM", CGRect(x: 325.5, y: 245.5, width: 49.5, height: 11.5))
            label("SIG", CGRect(x: 326, y: 263, width: 49, height: 12.5))
            ForEach(0..<3, id: \.self) { row in
                Bar().fill(style.ink).frame(width: 31, height: 5.5).offset(x: 387.5, y: 230 + 18 * CGFloat(row))
            }
            Rectangle().fill(style.ink).frame(width: 114.5, height: 3).offset(x: 318.5, y: 283)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.saira)
                    .placed(in: CGRect(x: 164.5, y: 313, width: 13, height: 16.5), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: Self.timeGlyph, trailing: Self.timeTrailing,
                baseline: Self.timeBaseline, xScale: Self.timeScale, colonGap: Self.colonGap,
                tracking: Self.timeTracking, style: style)
            LiveSeconds(
                context: context, glyph: Self.secondsGlyph, trailing: Self.secondsTrailing,
                baseline: Self.secondsBaseline, xScale: Self.secondsScale, tracking: Self.secondsTracking, style: style)
            Rectangle().fill(style.ink).frame(width: 287, height: 3).offset(x: 147, y: 393)
            // Year as "20 24", month, a short dash, day.
            bottomDigits(String(year.prefix(2)), trailing: Self.yearCenturyTrailing)
            bottomDigits(String(year.suffix(2)), trailing: Self.yearTrailing)
            bottomDigits(
                DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), trailing: Self.monthTrailing)
            Rectangle().fill(style.ink).frame(width: 6, height: 4.5).offset(x: 348, y: 419)
            bottomDigits(
                DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), trailing: Self.dayTrailing)
        }
        .lcdSegmentShadow(style)
        .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    private func label(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.6)
    }

    private func bottomDigits(_ text: String, trailing: CGFloat) -> some View {
        LCDText(
            text: text, font: style.digits, glyph: Self.bottomGlyph, edge: .trailing(trailing),
            baseline: Self.bottomBaseline, xScale: Self.bottomScale, style: style)
    }

    // Measured on the W-800H image (canvas points).
    static let weekdayGlyph: CGFloat = 39
    static let weekdayLeading: CGFloat = 188.5
    static let weekdayBaseline: CGFloat = 274
    static let weekdayTracking: CGFloat = 2
    static let weekdayScale: CGFloat = 1
    static let timeGlyph: CGFloat = 84
    static let timeTrailing: CGFloat = 342.5
    static let timeBaseline: CGFloat = 383
    static let timeScale: CGFloat = 0.78
    static let timeTracking: CGFloat = -13.4
    static let colonGap: CGFloat = 10
    static let secondsScale: CGFloat = 0.8
    static let secondsTracking: CGFloat = -8.1
    static let secondsGlyph: CGFloat = 62
    static let secondsTrailing: CGFloat = 419.5
    static let secondsBaseline: CGFloat = 383
    static let bottomGlyph: CGFloat = 35.5
    static let bottomBaseline: CGFloat = 438.5
    static let bottomScale: CGFloat = 0.89
    static let yearCenturyTrailing: CGFloat = 225
    static let yearTrailing: CGFloat = 288.5
    static let monthTrailing: CGFloat = 344
    static let dayTrailing: CGFloat = 409.5
}

/// One of the slanted SNZ / ALM / SIG bars.
private struct Bar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let slant = rect.height * 0.8
        path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
