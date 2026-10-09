import SwiftUI

/// The display of Casio's module 593 (F-91W, A158W, A168W, …): PM / 24H, weekday, date, H:MM and
/// live seconds. Measured once, from the F-91W photo, in its 389.5 × 184.5 glass; every model with
/// this module places it in its own glass (LCDModuleDisplay.placed(in:)).
struct Module593Display: LCDModuleDisplay {
    /// The glass the layout was measured in.
    static let glass = CGSize(width: 389.5, height: 184.5)

    let context: CasioFaceContext
    let style: LCDStyle

    /// Width of the big digits relative to DSEG's (the module's digits are narrower).
    static let digitSqueeze: CGFloat = 0.9

    // Measured character runs (canvas points).
    static let weekday = LCDRun(glyph: 43, edge: .leading(130), baseline: 55.5, tracking: 7.5)
    static let day = LCDRun(glyph: 47.5, edge: .trailing(380.7), baseline: 60, tracking: 4.5, width: 120)
    static let time = LCDRun(glyph: 88.5, edge: .trailing(279), baseline: 166, xScale: digitSqueeze)
    static let seconds = LCDRun(glyph: 67, edge: .trailing(382), baseline: 166, xScale: digitSqueeze)
    static let runs = [weekday, day, time, seconds]

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            // PM in the afternoon on a 12-hour clock (measured on the F-91W photo); 24H on a 24-hour
            // clock, a smaller mark further right (measured on the A158W photo).
            if parts.marker == "PM" {
                Text("PM")
                    .font(.system(size: 29.3, weight: .bold))
                    .foregroundStyle(style.ink)
                    .place(centerX: 37, centerY: 52)
            } else if parts.marker == "24H" {
                Text("24H")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(style.ink)
                    .place(centerX: 87.3, centerY: 53.1)
            }
            // Day of week and date share the top row.
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }
}
