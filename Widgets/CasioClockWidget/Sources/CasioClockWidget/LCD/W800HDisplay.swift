import SwiftUI

/// The W-800H's display (named after the watch; its module number is not checked here): a boxed
/// three-letter weekday, SNZ / ALM / SIG with their bars, P for PM, a large H:MM and seconds, and
/// the year and month-date under a divider, in upright 7-segment characters. Measured on a
/// front-on product image of the W-800H, in that face's canvas coordinates; `canvasOrigin` is where
/// its 294.5 × 259 glass sits on that canvas (`placed(in:)`). The bars show the alarms on, as in the
/// image.
struct W800HDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 294.5, height: 259)
    /// The glass's top-left corner on the W-800H canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 140, y: 202.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.year, .month, .day], from: context.date)
        let year = String(format: "%04d", date.year ?? 2000)
        inGlass(style: style) {
            RoundedRectangle(cornerRadius: 7).stroke(style.ink, lineWidth: 2.5)
                .frame(width: 143, height: 62).offset(x: 165.25, y: 224.25)
            LCDText(
                text: DisplayParts.weekday3(for: context.date, calendar: context.calendar), font: style.letters,
                run: Self.weekday, style: style)
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
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
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
    }

    private func label(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.6)
    }

    private func bottomDigits(_ text: String, trailing: CGFloat) -> some View {
        LCDText(text: text, font: style.digits, run: Self.bottomRow.trailing(trailing), style: style)
    }

    // Measured on the W-800H image (canvas points).
    static let weekday = LCDRun(glyph: 39, edge: .leading(188.5), baseline: 274, xScale: 1, tracking: 2)
    static let time = LCDRun(
        glyph: 84, edge: .trailing(342.5), baseline: 383, xScale: 0.78, tracking: -13.4, colonGap: 10)
    static let seconds = LCDRun(glyph: 62, edge: .trailing(417.5), baseline: 383, xScale: 0.8, tracking: -8.1)
    /// Anchored at its last group; the other groups use `.trailing(_:)`.
    static let bottomRow = LCDRun(glyph: 35.5, edge: .trailing(409.5), baseline: 438.5, xScale: 0.89)
    static let runs = [weekday, time, seconds, bottomRow]
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
