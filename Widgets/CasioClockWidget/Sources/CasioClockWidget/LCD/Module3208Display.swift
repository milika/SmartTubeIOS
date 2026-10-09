import SwiftUI

/// The display of Casio's module 3208 (CA-53W calculator watch): weekday top right, H:MM with a
/// wide colon and seconds as large as the minutes, upright 7-segment characters; a PM dot at the
/// top left on a 12-hour clock. Measured on the CA-53W photo, in that face's canvas coordinates;
/// `canvasOrigin` is where its 429 × 173 glass sits on that canvas (`placed(in:)`).
struct Module3208Display: LCDModuleDisplay {
    static let glass = CGSize(width: 429, height: 173)
    /// The glass's top-left corner on the CA-53W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 106.5, y: 116)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            if parts.isPM {
                Rectangle().fill(style.ink).frame(width: 9, height: 9).offset(x: 122, y: 130)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the CA-53W photo (canvas points).
    static let weekday = LCDRun(glyph: 47.5, edge: .trailing(519), baseline: 180, xScale: 0.95, tracking: 0)
    static let time = LCDRun(glyph: 71.5, edge: .trailing(369), baseline: 267, xScale: 0.86, colonGap: 48.5)
    static let seconds = LCDRun(glyph: 71.5, edge: .trailing(528.5), baseline: 265, xScale: 0.895)
    static let runs = [weekday, time, seconds]
}
