import SwiftUI

/// The display of Casio's module 240 (the first G-Shock, DW-5000C): weekday, a boxed month-first
/// date, 24H / PM, H:MM with a wide colon and live seconds. Measured on the DW-5000C photo, in that
/// face's canvas coordinates; `canvasOrigin` is where its 317.5 × 190.5 glass sits on that canvas,
/// so the layout lands in any model's glass (`placed(in:)`).
struct Module240Display: LCDModuleDisplay {
    static let glass = CGSize(width: 317.5, height: 190.5)
    /// The glass's top-left corner on the DW-5000C canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 152, y: 163.5)

    let context: CasioFaceContext
    let style: LCDStyle

    // Measured character runs (canvas points).
    // The weekday's two letters sit in fixed cells; the first cell is double width, and a W fills it
    // as two narrow cells, an L and a U (as on the DW-5000C photo).
    static let firstLetter = LCDRun(glyph: 36, edge: .leading(173), baseline: 218.5)
    static let doubleWLeft = LCDRun(glyph: 36, edge: .leading(171.5), baseline: 218.5, xScale: 0.9)
    static let doubleWRight = LCDRun(glyph: 36, edge: .leading(186), baseline: 218.5, xScale: 0.94)
    static let secondLetter = LCDRun(glyph: 36, edge: .leading(224.5), baseline: 218.5, xScale: 0.83)
    static let date = LCDRun(glyph: 44, edge: .trailing(456), baseline: 230.5, xScale: 0.877)
    static let time = LCDRun(glyph: 74.5, edge: .trailing(378), baseline: 335.5, xScale: 0.83, colonGap: 9.5)
    static let seconds = LCDRun(glyph: 53, edge: .trailing(461), baseline: 335.5, xScale: 0.83)
    static let runs = [firstLetter, doubleWLeft, doubleWRight, secondLetter, date, time, seconds]

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            let first = String(parts.weekday.prefix(1)), second = String(parts.weekday.dropFirst())
            if first == "W" {
                LCDText(text: "L", font: style.letters, run: Self.doubleWLeft, style: style)
                LCDText(text: "U", font: style.letters, run: Self.doubleWRight, style: style)
            } else {
                LCDText(text: first, font: style.letters, run: Self.firstLetter, style: style)
            }
            LCDText(text: second, font: style.letters, run: Self.secondLetter, style: style)
            if let marker = parts.marker {
                InkText(text: marker, font: CaseFont.michroma)
                    .placed(
                        in: CGRect(x: 228.5, y: 235.5, width: marker == "24H" ? 41 : 28, height: 15.5),
                        color: style.ink, bold: 0.6)
            }
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(style.ink, lineWidth: 2)
                .frame(width: 158, height: 63.5)
                .offset(x: 299, y: 176)
            LCDText(
                text: Self.dateText(context.date, calendar: context.calendar, blank: style.digits.blankDigit),
                font: style.digits, run: Self.date, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    /// Month first, as on the DW-5000C ("11- 4", " 6-28"), each number right-aligned in two digits.
    static func dateText(_ date: Date, calendar: Calendar, blank: String) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        return DisplayParts.twoCells(components.month ?? 1, blank: blank) + "-"
            + DisplayParts.twoCells(components.day ?? 1, blank: blank)
    }
}
