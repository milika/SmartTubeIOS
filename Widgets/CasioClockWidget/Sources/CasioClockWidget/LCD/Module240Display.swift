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

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            LCDText(
                text: parts.weekday, font: style.letters, glyph: 36, edge: .leading(173), baseline: 218.5,
                // The DW-5000C's W is double width; DSEG's is not. Wide enough for WE, not too wide for FR.
                tracking: 10, style: style)
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
                font: style.digits, glyph: 44, edge: .trailing(456), baseline: 230.5, xScale: 0.877, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: 74.5, trailing: 378, baseline: 335.5, xScale: 0.83,
                colonGap: 9.5, style: style)
            LiveSeconds(
                context: context, glyph: 53, trailing: 461, baseline: 335.5, xScale: 0.83, style: style)
        }
    }

    /// Month first, as on the DW-5000C ("11- 4", " 6-28"), each number right-aligned in two digits.
    static func dateText(_ date: Date, calendar: Calendar, blank: String) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        return DisplayParts.twoCells(components.month ?? 1, blank: blank) + "-"
            + DisplayParts.twoCells(components.day ?? 1, blank: blank)
    }
}
