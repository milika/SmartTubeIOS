import SwiftUI

/// The display of Casio's module 3298 (A168W): hourly-signal and alarm marks and PM on the left,
/// weekday and date top right, a large H:MM and smaller seconds, italic 7-segment characters.
/// Measured on Casio's A168WA-1W product image, in that face's canvas coordinates; `canvasOrigin`
/// is where its 280.5 × 138 glass sits on that canvas (`placed(in:)`). The signal and alarm marks
/// are shown on, as in the image.
struct Module3298Display: LCDModuleDisplay {
    static let glass = CGSize(width: 280.5, height: 138)
    /// The glass's top-left corner on the A168W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 136, y: 171)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            SignalMark().fill(style.ink).frame(width: 29, height: 11.5).offset(x: 156.5, y: 184)
            BellMark().fill(style.ink).frame(width: 13, height: 18.5).offset(x: 196, y: 182.5)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.saira)
                    .placed(in: CGRect(x: 156.5, y: 204.5, width: 27, height: 14.5), color: style.ink, bold: 0.6)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            LCDText(text: parts.day, font: style.digits, run: Self.day, style: style)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the A168W image (canvas points).
    static let weekday = LCDRun(glyph: 30, edge: .leading(260), baseline: 217.5, tracking: 6)
    static let day = LCDRun(glyph: 33, edge: .trailing(391), baseline: 219.5, width: 120)
    static let time = LCDRun(glyph: 63.5, edge: .trailing(336), baseline: 297, xScale: 0.913)
    static let seconds = LCDRun(glyph: 47, edge: .trailing(403), baseline: 297.5, xScale: 0.82)
    static let runs = [weekday, day, time, seconds]
}
