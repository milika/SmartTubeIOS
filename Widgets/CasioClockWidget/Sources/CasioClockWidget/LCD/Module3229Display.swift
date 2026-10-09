import SwiftUI

/// The display of Casio's module 3229 (DW-5600E): signal and alarm marks, the weekday, a boxed
/// month-date, PM, the EL light mark and a large italic H:MM with seconds. Measured on a front-on
/// product image of the DW-5600E, in that face's canvas coordinates; `canvasOrigin` is where its
/// 392.5 × 248 glass sits on that canvas (`placed(in:)`). The marks are shown on, as in the image.
struct Module3229Display: LCDModuleDisplay {
    static let glass = CGSize(width: 392.5, height: 248)
    /// The glass's top-left corner on the DW-5600E canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 240, y: 243.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.month, .day], from: context.date)
        ZStack(alignment: .topLeading) {
            SignalMark().fill(style.ink).frame(width: 35.5, height: 13.5).offset(x: 255, y: 286.5)
            BellMark().fill(style.ink).frame(width: 22, height: 27).offset(x: 261.5, y: 308)
            LCDText(
                text: DisplayParts.sevenSegmentLetters(parts.weekday), font: style.letters, glyph: Self.weekdayGlyph,
                edge: .leading(Self.weekdayLeading), baseline: Self.weekdayBaseline, tracking: Self.weekdayTracking,
                xScale: Self.weekdayScale, style: style)
            RoundedRectangle(cornerRadius: 9).stroke(style.ink, lineWidth: 2.5)
                .frame(width: 212, height: 88).offset(x: 412.75, y: 261.75)
            // Month, a short dash, day (the dash is narrower than a digit cell on this display).
            dateDigits(
                DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), trailing: Self.monthTrailing)
            Rectangle().fill(style.ink).frame(width: 16.5, height: 6).offset(x: 506, y: Self.dashTop)
            dateDigits(
                DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), trailing: Self.dateTrailing)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.saira)
                    .placed(in: CGRect(x: 259.5, y: 352.5, width: 37, height: 20.5), color: style.ink, bold: 0.6)
            }
            SunMark().stroke(style.ink, lineWidth: 2.5).frame(width: 49.5, height: 33.5).offset(x: 553, y: 361.5)
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

    private func dateDigits(_ text: String, trailing: CGFloat) -> some View {
        LCDText(
            text: text, font: style.digits, glyph: Self.dateGlyph, edge: .trailing(trailing),
            baseline: Self.dateBaseline,
            width: 160, tracking: Self.dateTracking, xScale: Self.dateScale, style: style)
    }

    // Measured on the DW-5600E image (canvas points).
    static let weekdayGlyph: CGFloat = 54
    static let weekdayLeading: CGFloat = 299
    static let weekdayBaseline: CGFloat = 337.5
    static let weekdayTracking: CGFloat = 7
    static let weekdayScale: CGFloat = 1
    static let dateGlyph: CGFloat = 59.5
    static let dateTrailing: CGFloat = 617
    static let monthTrailing: CGFloat = 506.5
    static let dashTop: CGFloat = 302
    static let dateBaseline: CGFloat = 335
    static let dateScale: CGFloat = 0.76
    static let dateTracking: CGFloat = 10.9
    static let timeGlyph: CGFloat = 95.5
    static let timeTrailing: CGFloat = 531.5
    static let colonGap: CGFloat = -13
    static let timeBaseline: CGFloat = 478
    static let timeScale: CGFloat = 0.76
    static let timeTracking: CGFloat = 12.8
    static let secondsGlyph: CGFloat = 67
    static let secondsTrailing: CGFloat = 622.5
    static let secondsBaseline: CGFloat = 473.5
    static let secondsScale: CGFloat = 0.82
    static let secondsTracking: CGFloat = 2.6
}

/// The EL light mark: a small sun - a disc with rays.
private struct SunMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = min(rect.width, rect.height) * 0.22
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner))
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            let start = CGPoint(x: center.x + cos(angle) * inner * 1.5, y: center.y + sin(angle) * inner * 1.5)
            let end = CGPoint(
                x: center.x + cos(angle) * rect.width * 0.48, y: center.y + sin(angle) * rect.height * 0.48)
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }
}
