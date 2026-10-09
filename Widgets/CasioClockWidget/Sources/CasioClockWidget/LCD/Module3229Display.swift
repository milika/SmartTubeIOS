import SwiftUI

/// The display of Casio's module 3229 (DW-5600E): signal and alarm marks, the weekday, a boxed
/// month-date, PM, the EL light mark and a large italic H:MM with seconds. Measured on a front-on
/// product image of the DW-5600E, in that face's canvas coordinates; `canvasOrigin` is where its
/// 392.5 × 248 glass sits on that canvas (`placed(in:)`). The marks are shown on, as in the image.
struct Module3229Display: LCDModuleDisplay {
    static let glass = CGSize(width: 392.5, height: 248)
    /// The glass's top-left corner on the DW-5600E canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 240, y: 243.5)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.month, .day], from: context.date)
        inGlass(style: style) {
            SignalMark().fill(style.ink).frame(width: 35.5, height: 15.5).offset(x: 255, y: 286.5)
            BellMark().fill(style.ink).frame(width: 22, height: 27).offset(x: 261.5, y: 308)
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
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
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    private func dateDigits(_ text: String, trailing: CGFloat) -> some View {
        LCDText(text: text, font: style.digits, run: Self.date.trailing(trailing), style: style)
    }

    // Measured on the DW-5600E image (canvas points).
    static let weekday = LCDRun(glyph: 54, edge: .leading(299), baseline: 337.5, xScale: 1, tracking: 7)
    static let time = LCDRun(
        glyph: 95.5, edge: .trailing(531.5), baseline: 478, xScale: 0.76, tracking: 12.8, colonGap: -13)
    static let seconds = LCDRun(glyph: 67, edge: .trailing(622.5), baseline: 473.5, xScale: 0.82, tracking: 2.6)
    /// Anchored at its last group; the other groups use `.trailing(_:)`.
    static let date = LCDRun(
        glyph: 59.5, edge: .trailing(617), baseline: 335, xScale: 0.76, tracking: 10.9, width: 160)
    static let runs = [weekday, time, seconds, date]
    static let dateTrailing: CGFloat = 617
    static let monthTrailing: CGFloat = 506.5
    static let dashTop: CGFloat = 302
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
