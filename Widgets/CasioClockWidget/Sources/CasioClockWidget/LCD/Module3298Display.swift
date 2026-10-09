import SwiftUI

/// The display of Casio's module 3298 (A168W): hourly-signal and alarm marks and PM on the left,
/// weekday and date top right, a large H:MM and smaller seconds, italic 7-segment characters.
/// Measured on Casio's A168WA-1W product image, in that face's canvas coordinates; `canvasOrigin`
/// is where its 280.5 × 138 glass sits on that canvas (`placed(in:)`). The signal and alarm marks
/// are shown on, as in the image.
struct Module3298Display: LCDModuleDisplay {
    static let glass = CGSize(width: 280.5, height: 138)
    /// The glass's top-left corner on the A168W canvas the numbers below were measured on.
    private static let canvasOrigin = CGPoint(x: 136, y: 171)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
            SignalMark().fill(style.ink).frame(width: 18, height: 11.5).offset(x: 156.5, y: 184)
            BellMark().fill(style.ink).frame(width: 13, height: 18.5).offset(x: 196, y: 182.5)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.saira)
                    .placed(in: CGRect(x: 156.5, y: 204.5, width: 27, height: 14.5), color: style.ink, bold: 0.6)
            }
            LCDText(
                text: DisplayParts.sevenSegmentLetters(parts.weekday), font: style.letters, glyph: Self.weekdayGlyph,
                edge: .leading(Self.weekdayLeading), baseline: Self.weekdayBaseline, tracking: Self.weekdayTracking,
                style: style)
            LCDText(
                text: parts.day, font: style.digits, glyph: Self.dateGlyph, edge: .trailing(Self.dateTrailing),
                baseline: Self.dateBaseline, width: 120, style: style)
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

    // Measured on the A168W image (canvas points).
    static let weekdayGlyph: CGFloat = 30
    static let weekdayLeading: CGFloat = 260
    static let weekdayBaseline: CGFloat = 217.5
    static let weekdayTracking: CGFloat = 6
    static let dateGlyph: CGFloat = 33
    static let dateTrailing: CGFloat = 391
    static let dateBaseline: CGFloat = 219.5
    static let timeGlyph: CGFloat = 63.5
    static let timeTrailing: CGFloat = 336
    static let timeBaseline: CGFloat = 297
    static let timeScale: CGFloat = 0.913
    static let secondsGlyph: CGFloat = 47
    static let secondsTrailing: CGFloat = 403
    static let secondsBaseline: CGFloat = 297.5
    static let secondsScale: CGFloat = 0.82
}

/// The hourly-signal mark: three bars and a sound arc.
private struct SignalMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let barWidth = rect.width * 0.14
        for index in 0..<3 {
            path.addRect(
                CGRect(
                    x: rect.minX + CGFloat(index) * rect.width * 0.24, y: rect.minY, width: barWidth,
                    height: rect.height))
        }
        let arc = Path { arc in
            arc.addArc(
                center: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.midY), radius: rect.width * 0.42,
                startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
        }
        path.addPath(arc.strokedPath(StrokeStyle(lineWidth: barWidth, lineCap: .butt)))
        return path
    }
}

/// The alarm mark: a bell with its clapper.
private struct BellMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width, height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + width * x, y: rect.minY + height * y)
        }
        path.move(to: point(0.5, 0))
        path.addCurve(to: point(0.12, 0.78), control1: point(0.15, 0), control2: point(0.2, 0.55))
        path.addLine(to: point(0, 0.86))
        path.addLine(to: point(1, 0.86))
        path.addLine(to: point(0.88, 0.78))
        path.addCurve(to: point(0.5, 0), control1: point(0.8, 0.55), control2: point(0.85, 0))
        path.closeSubpath()
        path.addEllipse(
            in: CGRect(
                x: rect.midX - width * 0.15, y: rect.minY + height * 0.86, width: width * 0.3, height: height * 0.14))
        return path
    }
}
