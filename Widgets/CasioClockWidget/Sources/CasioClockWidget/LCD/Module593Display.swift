import SwiftUI

/// Where module 593's characters sit (PM / 24H, weekday, date, H:MM, live seconds), measured on one
/// watch's photo. The module is the same in every watch, but each case shows it through a slightly
/// different window and the photos differ, so each watch whose photo shows it differently gets its
/// own measured layout (`Module593Display` from the F-91W, `A158WDisplay`).
struct Module593Layout {
    var weekday: LCDRun
    var day: LCDRun
    var time: LCDRun
    var seconds: LCDRun
    /// Centre and font size of the PM mark (12-hour clock, afternoon).
    var pm: CGPoint
    var pmSize: CGFloat
    /// Centre and font size of the smaller 24H mark (24-hour clock).
    var h24: CGPoint
    var h24Size: CGFloat
    /// Horizontal stretch of the 24H mark (the system font is narrower than some watches' print).
    var h24Stretch: CGFloat = 1

    var runs: [LCDRun] { [weekday, day, time, seconds] }

    @ViewBuilder
    func characters(context: CasioFaceContext, style: LCDStyle) -> some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        if parts.marker == "PM" {
            Text("PM")
                .font(.system(size: pmSize, weight: .bold))
                .foregroundStyle(style.ink)
                .place(centerX: pm.x, centerY: pm.y)
        } else if parts.marker == "24H" {
            Text("24H")
                .font(.system(size: h24Size, weight: .medium))
                .foregroundStyle(style.ink)
                .scaleEffect(x: h24Stretch, y: 1)
                .place(centerX: h24.x, centerY: h24.y)
        }
        // Day of week and date share the top row.
        LCDText(text: parts.weekday, font: style.letters, run: weekday, style: style)
        LCDText(text: parts.day, font: style.digits, run: day, style: style)
        LiveHoursMinutes(context: context, font: style.digits, run: time, style: style)
        LiveSeconds(context: context, run: seconds, style: style)
    }
}

/// The display of Casio's module 593 (F-91W, A158W, …) as the F-91W photo shows it. The characters
/// were measured relative to a point 3.5 pt right of and 6.5 pt below the glass's corner (`canvasOrigin`);
/// the glass is 391 × 192.5. A watch without its own measurement places it in its glass
/// (LCDModuleDisplay.placed(in:)).
struct Module593Display: LCDModuleDisplay {
    static let glass = CGSize(width: 391, height: 192.5)
    static let canvasOrigin = CGPoint(x: -3.5, y: -6.5)

    let context: CasioFaceContext
    let style: LCDStyle

    /// Width of the big digits relative to DSEG's (the module's digits are narrower).
    static let digitSqueeze: CGFloat = 0.9

    // Measured on the F-91W photo (glass points). The 24H mark was measured on the A158W photo.
    static let layout = Module593Layout(
        weekday: LCDRun(glyph: 43, edge: .leading(130), baseline: 55.5, tracking: 7.5),
        day: LCDRun(glyph: 47.5, edge: .trailing(380.7), baseline: 60, tracking: 4.5, width: 120),
        time: LCDRun(glyph: 88.5, edge: .trailing(279), baseline: 166, xScale: digitSqueeze),
        seconds: LCDRun(glyph: 67, edge: .trailing(382), baseline: 166, xScale: digitSqueeze),
        pm: CGPoint(x: 37, y: 52), pmSize: 29.3, h24: CGPoint(x: 87.3, y: 53.1), h24Size: 22)
    static let runs = layout.runs

    var body: some View {
        inGlass(style: style) { Self.layout.characters(context: context, style: style) }
    }
}
