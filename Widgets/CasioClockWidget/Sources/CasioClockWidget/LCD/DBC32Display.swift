import SwiftUI

/// The DBC-32 Databank's display (named after the watch; its module number is not checked here):
/// the weekday in 5×5 block letters top left under a stepped rule, AUTO LIGHT / 3 sec. / MUTE with
/// their boxes top right, a large H:MM and seconds, the year as "20 21" and the month-date below,
/// and "al-1 al-2 al-4" printed along the bottom. Slanted 7-segment digits. Measured on a front-on
/// photo of a DBC-32, in that face's canvas coordinates; `canvasOrigin` is where its 400.5 × 230
/// glass sits on that canvas (`placed(in:)`). The 3 sec. box is filled, as on the photo.
struct DBC32Display: LCDModuleDisplay {
    static let glass = CGSize(width: 400.5, height: 230)
    /// The glass's top-left corner on the DBC-32 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 111.5, y: 122)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.year, .month, .day], from: context.date)
        let year = String(format: "%04d", date.year ?? 2000)
        let blank = style.digits.blankDigit
        inGlass(style: style) {
            DotMatrixText(
                text: DisplayParts.weekday3(for: context.date, calendar: context.calendar),
                pitch: CGSize(width: 10.65, height: 7), dot: CGSize(width: 9.5, height: 6), advance: 64.5,
                narrowAdvance: 32, color: style.ink, glyphs: .block5x5, slant: 0.065
            )
            .frame(width: 200, height: 36, alignment: .topLeading)
            .offset(x: 172, y: 136)
            WeekdayRule().stroke(style.ink, lineWidth: 2)
            indicators
            if parts.isPM {
                InkText(text: "P", font: CaseFont.saira)
                    .placed(in: CGRect(x: 150, y: 202, width: 13, height: 16.5), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
            bottomDigits(String(year.prefix(2)), trailing: Self.yearCenturyTrailing)
            bottomDigits(String(year.suffix(2)), trailing: Self.yearTrailing)
            bottomDigits(DisplayParts.twoCells(date.month ?? 1, blank: blank), trailing: Self.monthTrailing)
            Dash().fill(style.ink).frame(width: 12, height: 5).offset(x: 409.5, y: 302.5)
            bottomDigits(DisplayParts.twoCells(date.day ?? 1, blank: blank), trailing: Self.dayTrailing)
            label("al-1", CGRect(x: 185, y: 337, width: 35, height: 13))
            label("al-2", CGRect(x: 238.5, y: 337, width: 37, height: 13))
            label("al-4", CGRect(x: 348.5, y: 336.5, width: 37, height: 13.5))
        }
    }

    /// AUTO LIGHT, 3 sec. and MUTE, each after a small printed box (fainter than the segments); the
    /// 3 sec. box is filled.
    private var indicators: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { row in
                Rectangle().stroke(style.ink.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 8.5, height: 8.5).offset(x: 375, y: 127.5 + 14 * CGFloat(row))
            }
            Rectangle().fill(style.ink).frame(width: 9, height: 7).offset(x: 374.5, y: 143.5)
            label("AUTO LIGHT", CGRect(x: 392, y: 127, width: 103, height: 10.5))
            label("3 sec.", CGRect(x: 394.5, y: 141, width: 44, height: 10))
            label("MUTE", CGRect(x: 391, y: 154.5, width: 44.5, height: 11.5))
        }
    }

    private func label(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.5)
    }

    private func bottomDigits(_ text: String, trailing: CGFloat) -> some View {
        LCDText(text: text, font: style.digits, run: Self.bottomRow.trailing(trailing), style: style)
    }

    // Measured on the DBC-32 photo (canvas points).
    static let time = LCDRun(
        glyph: 68, edge: .trailing(361.5), baseline: 268, xScale: 0.895, tracking: -1.7, colonGap: 41.7)
    static let seconds = LCDRun(glyph: 68, edge: .trailing(509), baseline: 267, xScale: 0.895, tracking: -0.8)
    /// Anchored at its last group; the other groups use `.trailing(_:)`.
    static let bottomRow = LCDRun(glyph: 36, edge: .trailing(495.5), baseline: 325.5, xScale: 1.16)
    static let runs = [time, seconds, bottomRow]
    static let yearCenturyTrailing: CGFloat = 212.5
    static let yearTrailing: CGFloat = 297
    static let monthTrailing: CGFloat = 408.5
    static let dayTrailing: CGFloat = 495.5
}

/// The rule under the weekday: level under the letters, stepping up towards the indicators.
private struct WeekdayRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 150, y: 180.5))
        path.addLine(to: CGPoint(x: 378, y: 179.5))
        path.addLine(to: CGPoint(x: 393, y: 169.75))
        path.addLine(to: CGPoint(x: 501, y: 169.75))
        return path
    }
}

/// The slanted dash between month and day.
private struct Dash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let slant = rect.height * 0.083
        path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
