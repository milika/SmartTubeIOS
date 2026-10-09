import SwiftUI

/// The display of Casio's module 3208 (CA-53W calculator watch): weekday top right, H:MM with a
/// wide colon and seconds as large as the minutes, upright 7-segment characters; a PM dot at the
/// top left on a 12-hour clock. Measured on the CA-53W photo, in that face's canvas coordinates;
/// `canvasOrigin` is where its 430 × 174.5 glass sits on that canvas (`placed(in:)`).
struct Module3208Display: LCDModuleDisplay {
    static let glass = CGSize(width: 430, height: 174.5)
    /// The glass's top-left corner on the CA-53W canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 108.5, y: 113.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
            if parts.isPM {
                Rectangle().fill(style.ink).frame(width: 9, height: 9).offset(x: 122, y: 130)
            }
            LCDText(
                text: Self.segmentLetters(parts.weekday), font: style.letters, glyph: Self.weekdayGlyph,
                edge: .trailing(Self.weekdayTrailing),
                baseline: Self.weekdayBaseline, tracking: Self.weekdayTracking, xScale: Self.weekdayScale, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: Self.timeGlyph, trailing: Self.timeTrailing,
                baseline: Self.timeBaseline, xScale: Self.timeScale, colonGap: Self.colonGap, style: style)
            LiveSeconds(
                context: context, glyph: Self.timeGlyph, trailing: Self.secondsTrailing,
                baseline: Self.secondsBaseline, xScale: Self.timeScale, style: style)
        }
        .lcdSegmentShadow(style)
        .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    /// The weekday as this module's 7-segment letters: S is drawn as a full "5", U as a full-height U
    /// (DSEG7's "V") and O as a full "0"; DSEG7's own S, U and O are small lower-case shapes.
    static func segmentLetters(_ weekday: String) -> String {
        String(weekday.map { ["S": "5", "U": "V", "O": "0"][$0] ?? $0 })
    }

    // Measured on the CA-53W photo (canvas points).
    static let weekdayGlyph: CGFloat = 47.5
    static let weekdayTrailing: CGFloat = 519
    static let weekdayBaseline: CGFloat = 180
    static let weekdayScale: CGFloat = 0.95
    static let weekdayTracking: CGFloat = 0
    static let timeGlyph: CGFloat = 71.5
    static let timeTrailing: CGFloat = 369
    static let timeBaseline: CGFloat = 267
    static let timeScale: CGFloat = 0.86
    static let colonGap: CGFloat = 51.5
    static let secondsTrailing: CGFloat = 529
    static let secondsBaseline: CGFloat = 265
}
