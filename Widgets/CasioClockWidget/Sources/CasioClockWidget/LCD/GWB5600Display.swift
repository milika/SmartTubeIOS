import SwiftUI

/// The GW-B5600's display (named after the watch; its module number is not checked here): PS / LT
/// / RCVD, the weekday, a boxed month.day date, the battery level, SNZ and the mute mark, P for
/// PM, and a large italic H:MM with seconds. Measured on a front-on product image of the
/// GW-B5600MG, in that face's canvas coordinates; `canvasOrigin` is where its 396 × 260.5 glass sits
/// on that canvas (`placed(in:)`). The marks are shown on, as in the image.
struct GWB5600Display: LCDModuleDisplay {
    static let glass = CGSize(width: 396, height: 260.5)
    /// The glass's top-left corner on the GW-B5600 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 115, y: 151.5)

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
            // Month.day in dot matrix, as on the GW-B5600 image ("6.30").
            DotMatrixText(
                text: DisplayParts.twoCells(date.month ?? 1, blank: " ") + "."
                    + DisplayParts.twoCells(date.day ?? 1, blank: " "),
                pitch: CGSize(width: 5.4, height: 8.1), dot: CGSize(width: 4.5, height: 6.8), advance: 35.5,
                narrowAdvance: 17.5, color: style.ink, glyphs: .bold5x7, slant: 0.06
            )
            .frame(width: 175, height: 60, alignment: .topLeading)
            .offset(x: 330.5, y: 187)
            BatteryMark().fill(style.ink).frame(width: 71.5, height: 18.5).offset(x: 423.5, y: 262)
            InkText(text: "SNZ", font: CaseFont.michroma)
                .placed(in: CGRect(x: 424, y: 293, width: 46, height: 14.5), color: style.ink, bold: 0.6)
            MuteMark().stroke(style.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .frame(width: 22, height: 22).offset(x: 479, y: 290)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 133.5, y: 278.5, width: 15, height: 19.5), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the GW-B5600 image (canvas points).
    static let weekday = LCDRun(glyph: 57.5, edge: .leading(205), baseline: 247, xScale: 0.97, tracking: 0)
    static let time = LCDRun(glyph: 104, edge: .trailing(397), baseline: 392, xScale: 0.77, tracking: 0, colonGap: 0)
    static let seconds = LCDRun(glyph: 67.5, edge: .trailing(502), baseline: 386.5, xScale: 0.88, tracking: 0)
    static let runs = [weekday, time, seconds]
}

/// The battery level: four bars, a square block, four bars (measured on the GW-B5600 image).
private struct BatteryMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bar = rect.width * 0.05, pitch = rect.width * 0.1
        for index in 0..<4 {
            path.addRect(CGRect(x: rect.minX + CGFloat(index) * pitch, y: rect.minY, width: bar, height: rect.height))
            path.addRect(
                CGRect(x: rect.maxX - bar - CGFloat(index) * pitch, y: rect.minY, width: bar, height: rect.height))
        }
        path.addRect(
            CGRect(
                x: rect.midX - rect.width * 0.08, y: rect.minY + rect.height * 0.1,
                width: rect.width * 0.16, height: rect.height * 0.8))
        return path
    }
}

/// The mute (operation tone off) mark: a speaker with a sound arc, struck through.
private struct MuteMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        // Speaker: a small box and its cone.
        path.addLines([
            point(0.08, 0.4), point(0.25, 0.4), point(0.5, 0.18), point(0.5, 0.82), point(0.25, 0.6),
            point(0.08, 0.6), point(0.08, 0.4),
        ])
        path.addArc(
            center: point(0.5, 0.5), radius: rect.width * 0.38, startAngle: .degrees(-55), endAngle: .degrees(55),
            clockwise: false)
        path.move(to: point(0.05, 0.95))
        path.addLine(to: point(0.95, 0.05))
        return path
    }
}
