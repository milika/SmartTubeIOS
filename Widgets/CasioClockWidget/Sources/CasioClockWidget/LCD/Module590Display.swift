import SwiftUI

/// The display of Casio's module 590 (W-59): 24H / PM, weekday, date, H:MM and live seconds - the
/// same elements as module 593 but placed differently. Measured on the W-59 photo, in that face's
/// canvas coordinates; `canvasOrigin` is where its 336.5 × 163.5 glass sits on that canvas, so the
/// layout lands in any model's glass (`placed(in:)`).
struct Module590Display: LCDModuleDisplay {
    static let glass = CGSize(width: 336.5, height: 163.5)
    /// The glass's top-left corner on the W-59 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 103, y: 160.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            if let marker = parts.marker {
                InkText(text: marker, font: CaseFont.saira)
                    .placed(
                        in: CGRect(x: 171.5, y: 206.5, width: marker == "24H" ? 29.5 : 21, height: 8),
                        color: style.ink, bold: 0.3)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the W-59 photo (canvas points).
    static let weekday = LCDRun(glyph: 34.5, edge: .leading(254), baseline: 215.5, tracking: 4.5)
    static let day = LCDRun(glyph: 36, edge: .trailing(411.5), baseline: 217, width: 120)
    static let time = LCDRun(glyph: 74, edge: .trailing(344.5), baseline: 309, xScale: 0.926)
    static let seconds = LCDRun(glyph: 53.5, edge: .trailing(425.5), baseline: 309.5, xScale: 0.85)
    static let runs = [weekday, day, time, seconds]
}
