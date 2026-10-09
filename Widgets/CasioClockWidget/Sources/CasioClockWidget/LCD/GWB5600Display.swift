import SwiftUI

/// The GW-B5600's display (named after the watch; its module number is not checked here): PS / LT
/// / RCVD, the weekday, a boxed month.day date, the battery level, SNZ and the Bluetooth mark, P for
/// PM, and a large italic H:MM with seconds. Measured on a front-on product image of the
/// GW-B5600MG, in that face's canvas coordinates; `canvasOrigin` is where its 396 × 258 glass sits
/// on that canvas (`placed(in:)`). The marks are shown on, as in the image.
struct GWB5600Display: LCDModuleDisplay {
    static let glass = CGSize(width: 396, height: 258)
    /// The glass's top-left corner on the GW-B5600 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 115, y: 154)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.month, .day], from: context.date)
        inGlass(style: style) {
            InkText(text: "PS LT RCVD", font: CaseFont.michroma)
                .placed(in: CGRect(x: 140.5, y: 165, width: 156, height: 17), color: style.ink, bold: 0.6)
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            RoundedRectangle(cornerRadius: 9).stroke(style.ink, lineWidth: 2.5)
                .frame(width: 182, height: 81.5).offset(x: 324.25, y: 174.25)
            dateDigits(DisplayParts.twoCells(date.month ?? 1, blank: style.digits.blankDigit), Self.monthTrailing)
            Rectangle().fill(style.ink).frame(width: 7, height: 7).offset(x: Self.dotX, y: Self.dateBaseline - 7)
            dateDigits(DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), Self.dateTrailing)
            BatteryMark().fill(style.ink).frame(width: 71.5, height: 18.5).offset(x: 423.5, y: 262)
            InkText(text: "SNZ", font: CaseFont.michroma)
                .placed(in: CGRect(x: 424, y: 293, width: 46, height: 14.5), color: style.ink, bold: 0.6)
            BluetoothMark().stroke(style.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .frame(width: 22, height: 22).offset(x: 479, y: 290)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 133.5, y: 278.5, width: 15, height: 19.5), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    private func dateDigits(_ text: String, _ trailing: CGFloat) -> some View {
        LCDText(text: text, font: style.digits, run: Self.date.trailing(trailing), style: style)
    }

    // Measured on the GW-B5600 image (canvas points).
    static let weekday = LCDRun(glyph: 57.5, edge: .leading(205), baseline: 247, xScale: 0.97, tracking: 0)
    static let time = LCDRun(glyph: 104, edge: .trailing(397), baseline: 392, xScale: 0.77, tracking: 0, colonGap: 0)
    static let seconds = LCDRun(glyph: 67.5, edge: .trailing(502), baseline: 386.5, xScale: 0.88, tracking: 0)
    /// Anchored at its last group; the other groups use `.trailing(_:)`.
    static let date = LCDRun(
        glyph: 55.5, edge: .trailing(486.5), baseline: 242.5, xScale: 0.83, tracking: 0, width: 160)
    static let runs = [weekday, time, seconds, date]
    static let dateBaseline: CGFloat = 242.5
    static let monthTrailing: CGFloat = 398.5
    static let dotX: CGFloat = 402
    static let dateTrailing: CGFloat = 486.5
}

/// The battery level: three bars, a battery with two cells, three bars.
private struct BatteryMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bar = rect.width * 0.035, gap = rect.width * 0.075
        for index in 0..<3 {
            path.addRect(CGRect(x: rect.minX + CGFloat(index) * gap, y: rect.minY, width: bar, height: rect.height))
            path.addRect(
                CGRect(x: rect.maxX - bar - CGFloat(index) * gap, y: rect.minY, width: bar, height: rect.height))
        }
        let body = CGRect(
            x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.12,
            width: rect.width * 0.42, height: rect.height * 0.76)
        path.addRect(body)
        return path
    }
}

/// The Bluetooth rune.
private struct BluetoothMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        path.move(to: point(0.2, 0.3))
        path.addLine(to: point(0.8, 0.72))
        path.addLine(to: point(0.5, 0.95))
        path.addLine(to: point(0.5, 0.05))
        path.addLine(to: point(0.8, 0.28))
        path.addLine(to: point(0.2, 0.7))
        return path
    }
}
