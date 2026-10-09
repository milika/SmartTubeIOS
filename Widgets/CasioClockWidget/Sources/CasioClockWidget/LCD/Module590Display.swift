import SwiftUI

/// The display of Casio's module 590 (W-59): 24H / PM, weekday, date, H:MM and live seconds - the
/// same elements as module 593 but placed differently. Measured on the W-59 photo, in that face's
/// canvas coordinates; `canvasOrigin` is where its 336.5 × 163.5 glass sits on that canvas, so the
/// layout lands in any model's glass (`placed(in:)`).
struct Module590Display: LCDModuleDisplay {
    static let glass = CGSize(width: 336.5, height: 163.5)
    /// The glass's top-left corner on the W-59 canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 103, y: 160.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
            if let marker = parts.marker {
                InkText(text: marker, font: CaseFont.saira)
                    .placed(
                        in: CGRect(x: 171.5, y: 206.5, width: marker == "24H" ? 29.5 : 21, height: 8),
                        color: style.ink, bold: 0.3)
            }
            LCDText(
                text: parts.weekday, font: style.letters, glyph: Self.weekdayGlyph, edge: .leading(Self.weekdayLeading),
                baseline: Self.weekdayBaseline, tracking: Self.weekdayTracking, style: style)
            LCDText(
                text: parts.day, font: style.digits, glyph: Self.dayGlyph, edge: .trailing(Self.dayTrailing),
                baseline: Self.dayBaseline, width: 120, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: Self.timeGlyph, trailing: Self.timeTrailing,
                baseline: Self.timeBaseline, xScale: Self.timeScale, style: style)
            LiveSeconds(
                context: context, glyph: Self.secondsGlyph, trailing: Self.secondsTrailing,
                baseline: Self.secondsBaseline, xScale: Self.secondsScale, style: style)
        }
        .lcdSegmentShadow(style)
        .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    // Measured on the W-59 photo (canvas points).
    static let weekdayGlyph: CGFloat = 34.5
    static let weekdayLeading: CGFloat = 254
    static let weekdayBaseline: CGFloat = 215.5
    static let weekdayTracking: CGFloat = 4.5
    static let dayGlyph: CGFloat = 36
    static let dayTrailing: CGFloat = 411.5
    static let dayBaseline: CGFloat = 217
    static let timeGlyph: CGFloat = 74
    static let timeTrailing: CGFloat = 344.5
    static let timeBaseline: CGFloat = 309
    static let timeScale: CGFloat = 0.926
    static let secondsGlyph: CGFloat = 53.5
    static let secondsTrailing: CGFloat = 425.5
    static let secondsScale: CGFloat = 0.85
    static let secondsBaseline: CGFloat = 309.5
}
