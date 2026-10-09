import SwiftUI

/// The W-86's display (named after the watch; its module number is not checked here): signal and
/// alarm marks, 24H (PM on a 12-hour clock), weekday and day of month on top, a large italic H:MM
/// and seconds below. Measured on a front-on photo of a W-86, in that face's canvas coordinates;
/// `canvasOrigin` is where its 536.5 × 255 glass sits on that canvas (`placed(in:)`). The marks are
/// shown on, as in the photo.
struct W86Display: LCDModuleDisplay {
    static let glass = CGSize(width: 536.5, height: 255)
    /// The glass's top-left corner on the W-86 canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 88, y: 200)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
            SignalMark().fill(style.ink).frame(width: 56, height: 20).offset(x: 129, y: 219.5)
            BellMark().fill(style.ink).frame(width: 26, height: 29.5).offset(x: 204.5, y: 214.5)
            if let marker = parts.marker {
                InkText(text: marker, font: CaseFont.michroma)
                    .placed(
                        in: CGRect(x: 187.5, y: 261, width: marker == "24H" ? 57 : 38, height: 20), color: style.ink,
                        bold: 0.6)
            }
            LCDText(
                text: parts.weekday, font: style.letters, glyph: Self.topGlyph,
                edge: .leading(Self.weekdayLeading), baseline: Self.topBaseline, tracking: Self.weekdayTracking,
                xScale: Self.weekdayScale, style: style)
            LCDText(
                text: parts.day, font: style.digits, glyph: Self.topGlyph, edge: .trailing(Self.dayTrailing),
                baseline: Self.topBaseline, width: 160, tracking: Self.dayTracking, xScale: Self.dayScale, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: Self.timeGlyph, trailing: Self.timeTrailing,
                baseline: Self.timeBaseline, xScale: Self.timeScale, colonGap: Self.colonGap,
                tracking: Self.timeTracking, style: style)
            LiveSeconds(
                context: context, glyph: Self.secondsGlyph, trailing: Self.secondsTrailing,
                baseline: Self.secondsBaseline, xScale: Self.secondsScale, tracking: Self.secondsTracking,
                style: style)
        }
        .lcdSegmentShadow(style)
        .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    // Measured on the W-86 photo (canvas points).
    static let topGlyph: CGFloat = 55
    static let topBaseline: CGFloat = 278
    static let weekdayLeading: CGFloat = 329.5
    static let weekdayTracking: CGFloat = 15.5
    static let weekdayScale: CGFloat = 1
    static let dayTrailing: CGFloat = 591
    static let dayScale: CGFloat = 1.14
    static let dayTracking: CGFloat = 5
    static let timeGlyph: CGFloat = 116
    static let timeTrailing: CGFloat = 482
    static let timeBaseline: CGFloat = 421
    static let timeScale: CGFloat = 0.9
    static let colonGap: CGFloat = 4
    static let timeTracking: CGFloat = 6.1
    static let secondsGlyph: CGFloat = 84
    static let secondsTrailing: CGFloat = 614
    static let secondsBaseline: CGFloat = 420.5
    static let secondsScale: CGFloat = 0.86
    static let secondsTracking: CGFloat = 5.4
}
