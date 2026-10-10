import SwiftUI

/// The DBC-32 face on its canvas (see CasioDBC32 for where the numbers come from): the case with
/// its side buttons, the print and LCD under the crystal, the ILLUMINATOR badge and the keypad.
struct DBC32Face: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioDBC32.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            caseShape
            crystal
            topPrint
            lcd
            badge
            keypad
        }
    }

    // MARK: Case

    private var caseShape: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.buttons.enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 3).fill(CasioDBC32.button)
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            }
            CaseOutline().fill(CasioDBC32.resin)
            CaseOutline().stroke(CasioDBC32.caseEdge, lineWidth: 2)
        }
    }

    /// The side buttons, two on each side.
    private static let buttons = [
        CGRect(x: 11, y: 130, width: 20, height: 115), CGRect(x: 3, y: 250, width: 28, height: 110),
        CGRect(x: 597, y: 130, width: 20, height: 115), CGRect(x: 597, y: 250, width: 28, height: 110),
    ]

    /// The crystal's rim; under it the black print band, the slate-blue plate and the LCD's frame.
    private var crystal: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CasioDBC32.resin)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(
                        CasioDBC32.rimEdge, lineWidth: 1.5)
                )
                .frame(width: 491, height: 336).offset(x: 62, y: 30)
            UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 14,
                style: .continuous
            )
            .fill(CasioDBC32.plate)
            .frame(width: 473, height: 326).offset(x: 72, y: 36)
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(CasioDBC32.band)
                .frame(width: 473, height: 45).offset(x: 72, y: 36)
        }
    }

    private func ink(_ text: String, _ box: CGRect, bold: CGFloat = 0.5, slant: CGFloat = 0) -> some View {
        InkText(text: text, font: CaseFont.michroma, slant: slant).placed(in: box, color: CasioDBC32.print, bold: bold)
    }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", CGRect(x: 128.5, y: 58, width: 107, height: 16), bold: 0.9)
            ink("Multi", CGRect(x: 268, y: 63, width: 43, height: 11))
            ink("Lingual", CGRect(x: 319.5, y: 63, width: 67, height: 14))
            ink("DATA", CGRect(x: 399, y: 61, width: 55.5, height: 13), bold: 0.8, slant: 0.25)
            ink("BANK", CGRect(x: 461, y: 60.5, width: 64.5, height: 12.5), bold: 0.8, slant: 0.25)
            ink("10", CGRect(x: 386.5, y: 85.5, width: 19.5, height: 11.5))
            ink("Year", CGRect(x: 413.5, y: 85.5, width: 41.5, height: 11.5))
            ink("Battery", CGRect(x: 462, y: 85, width: 66, height: 14))
        }
    }

    private var lcd: some View {
        LCDPanel(
            display: DBC32Display.self, frame: CGRect(x: 100, y: 102, width: 427, height: 253), frameRadius: 8,
            surround: CasioDBC32.lcdFrame, outline: .clear, outlineWidth: 0,
            glass: CGRect(x: 111.5, y: 122, width: 400.5, height: 230), glassRadius: 4, context: context,
            style: style)
    }

    // MARK: ILLUMINATOR

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(CasioDBC32.badgeBar)
                .frame(width: 494, height: 32).offset(x: 62, y: 368)
            BadgeOutline().stroke(CasioDBC32.silver, lineWidth: 1.5)
                .frame(width: 232, height: 22).offset(x: 320, y: 375)
            Arrow(pointsLeft: true).fill(CasioDBC32.silver).frame(width: 17, height: 11).offset(x: 327, y: 381)
            Arrow(pointsLeft: false).fill(CasioDBC32.silver).frame(width: 17, height: 11).offset(x: 528, y: 381)
            InkText(text: "ILLUMINATOR", font: CaseFont.sairaExpanded, slant: 0.25)
                .placed(in: CGRect(x: 348, y: 375, width: 170, height: 23), color: CasioDBC32.silver, bold: 0.6)
        }
    }

    // MARK: Keypad

    /// Key columns (left and right sides) and the rows' red rules (middle keys' height; the photo's
    /// lens bows the outer ones).
    private static let columns: [ClosedRange<CGFloat>] = [90...198.5, 210.5...307, 319...415.5, 428...536]
    private static let ruleColumns: [ClosedRange<CGFloat>] = [92...196.5, 209...304.5, 318...412.5, 427...528]
    private static let ruleY: [CGFloat] = [523.9, 585.9, 647.9, 709.9]

    private var keypad: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(CasioDBC32.keypad)
                .frame(width: 476, height: 326).offset(x: 76, y: 414)
            ForEach(0..<16, id: \.self) { index in
                key(column: index % 4, row: index / 4)
            }
            ForEach(0..<16, id: \.self) { index in
                let span = Self.ruleColumns[index % 4]
                Rectangle().fill(CasioDBC32.red)
                    .frame(width: span.upperBound - span.lowerBound, height: 4)
                    .offset(x: span.lowerBound, y: Self.ruleY[index / 4] - 2)
            }
            redMarks
            header
            keyLabels
        }
    }

    /// A key: its face, darker sides and the front lip above the rule.
    private func key(column: Int, row: Int) -> some View {
        let span = Self.columns[column]
        let bottom = Self.ruleY[row] - 4
        let top = bottom - 52
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(CasioDBC32.keyEdge).frame(width: span.upperBound - span.lowerBound, height: 52)
            Rectangle().fill(CasioDBC32.keypad)
                .frame(width: span.upperBound - span.lowerBound - 9, height: 40).offset(x: 4.5, y: 0)
            Rectangle().fill(CasioDBC32.keyLip)
                .frame(width: span.upperBound - span.lowerBound - 9, height: 6).offset(x: 4.5, y: 42)
        }
        .offset(x: span.lowerBound, y: top)
    }

    private var redMarks: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(CasioDBC32.red).frame(width: 10, height: 11).offset(x: 91.5, y: 423)
            Arrow(pointsLeft: true).fill(CasioDBC32.red).frame(width: 9, height: 8.5).offset(x: 93, y: 441)
            Rectangle().fill(CasioDBC32.red).frame(width: 10, height: 11).offset(x: 523, y: 423.5)
            Arrow(pointsLeft: false).fill(CasioDBC32.red).frame(width: 8, height: 8.5).offset(x: 522, y: 441.5)
        }
    }

    private func keyInk(_ text: String, _ box: CGRect, bold: CGFloat = 0.6) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: CasioDBC32.keyPrint, bold: bold)
    }

    /// ADJUST / MODE and LIGHT / AC,12/24H above the keys.
    private var header: some View {
        ZStack(alignment: .topLeading) {
            keyInk("ADJUST", CGRect(x: 112, y: 424, width: 79.5, height: 13))
            keyInk("MODE", CGRect(x: 112.5, y: 441, width: 58.5, height: 13))
            keyInk("LIGHT", CGRect(x: 451, y: 424.5, width: 59.5, height: 13.5))
            keyInk("AC", CGRect(x: 411.5, y: 441, width: 28, height: 14))
            keyInk(",", CGRect(x: 441, y: 451, width: 4, height: 6))
            keyInk("12", CGRect(x: 446.5, y: 441.5, width: 20, height: 13.5))
            keyInk("/", CGRect(x: 465, y: 441.5, width: 8.5, height: 13.5))
            keyInk("24H", CGRect(x: 474, y: 441.5, width: 35.5, height: 13.5))
        }
    }

    private var keyLabels: some View {
        ZStack(alignment: .topLeading) {
            Chevron(pointsLeft: true).stroke(CasioDBC32.keyPrint, lineWidth: 2.5)
                .frame(width: 8, height: 10.5).offset(x: 100, y: 474)
            keyInk("REV", CGRect(x: 113, y: 473.5, width: 34, height: 12.5))
            keyInk("/", CGRect(x: 145.5, y: 474, width: 5.5, height: 12))
            keyInk("TIME", CGRect(x: 151.5, y: 473.5, width: 39.5, height: 12.5))
            keyInk("TEL", CGRect(x: 432.5, y: 474, width: 30.5, height: 13))
            keyInk("/", CGRect(x: 462.5, y: 474, width: 6.5, height: 13))
            keyInk("FWD", CGRect(x: 469, y: 474, width: 38.5, height: 13))
            Chevron(pointsLeft: false).stroke(CasioDBC32.keyPrint, lineWidth: 2.5)
                .frame(width: 8, height: 10.5).offset(x: 513.5, y: 474.75)
            operators
            keyInk("7", CGRect(x: 136, y: 548, width: 16, height: 20.5), bold: 1)
            keyInk("8", CGRect(x: 247.5, y: 548.5, width: 17, height: 17), bold: 1)
            keyInk("9", CGRect(x: 356, y: 549, width: 17, height: 17), bold: 1)
            keyInk("0", CGRect(x: 467.5, y: 549, width: 18.5, height: 21), bold: 1)
            keyInk("4", CGRect(x: 135, y: 610.5, width: 18, height: 18.5), bold: 1)
            keyInk("5", CGRect(x: 248, y: 611, width: 16, height: 16), bold: 1)
            keyInk("6", CGRect(x: 356, y: 611, width: 16.5, height: 18), bold: 1)
            Rectangle().fill(CasioDBC32.keyPrint).frame(width: 3, height: 3).offset(x: 449.5, y: 626)
            keyInk("SPC", CGRect(x: 468.5, y: 613, width: 34.5, height: 17.5), bold: 0.8)
            keyInk("1", CGRect(x: 137.5, y: 672.5, width: 11.5, height: 18.5), bold: 1)
            keyInk("2", CGRect(x: 247.5, y: 672.5, width: 16.5, height: 16.5), bold: 1)
            keyInk("3", CGRect(x: 356, y: 673, width: 17, height: 16.5), bold: 1)
            Rectangle().fill(CasioDBC32.keyPrint).frame(width: 14.5, height: 3.5).offset(x: 443, y: 677.5)
            Rectangle().fill(CasioDBC32.keyPrint).frame(width: 14.5, height: 3.5).offset(x: 443, y: 683)
            keyInk("PM", CGRect(x: 468.5, y: 675.5, width: 25, height: 15.5), bold: 0.8)
        }
    }

    /// ÷ × − + on the top row.
    private var operators: some View {
        let white = CasioDBC32.keyPrint
        return ZStack(alignment: .topLeading) {
            // ÷
            Circle().fill(white).frame(width: 4.5, height: 4.5).offset(x: 141.5, y: 489.5)
            Rectangle().fill(white).frame(width: 17.5, height: 3.5).offset(x: 135, y: 497)
            Rectangle().fill(white).frame(width: 3.5, height: 8).offset(x: 142, y: 502)
            // ×
            ZStack {
                Rectangle().fill(white).frame(width: 20, height: 3).rotationEffect(.degrees(45))
                Rectangle().fill(white).frame(width: 20, height: 3).rotationEffect(.degrees(-45))
            }
            .frame(width: 15.5, height: 16.5)
            .offset(x: 248.5, y: 490)
            // −
            Rectangle().fill(white).frame(width: 17, height: 5).offset(x: 356, y: 495.5)
            // +
            Rectangle().fill(white).frame(width: 17, height: 3.5).offset(x: 468.5, y: 496)
            Rectangle().fill(white).frame(width: 3.5, height: 21).offset(x: 474.25, y: 490)
        }
    }
}

/// The case in front view: chamfered top corners, straight sides past the buttons, then narrowing
/// along the keypad to a rounded bottom (photo canvas points).
private struct CaseOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 72, y: 22))
        path.addLine(to: CGPoint(x: 556, y: 22))
        path.addLine(to: CGPoint(x: 600, y: 98))
        path.addLine(to: CGPoint(x: 600, y: 362))
        path.addQuadCurve(to: CGPoint(x: 588, y: 430), control: CGPoint(x: 600, y: 410))
        path.addLine(to: CGPoint(x: 571, y: 705))
        path.addQuadCurve(to: CGPoint(x: 540, y: 766), control: CGPoint(x: 571, y: 766))
        path.addLine(to: CGPoint(x: 88, y: 766))
        path.addQuadCurve(to: CGPoint(x: 57, y: 705), control: CGPoint(x: 57, y: 766))
        path.addLine(to: CGPoint(x: 40, y: 430))
        path.addQuadCurve(to: CGPoint(x: 28, y: 362), control: CGPoint(x: 28, y: 410))
        path.addLine(to: CGPoint(x: 28, y: 98))
        path.closeSubpath()
        return path
    }
}

/// The ILLUMINATOR badge's outline: a long plate with pointed ends.
private struct BadgeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let point = rect.height * 0.7
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + point, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A filled triangle pointing left or right.
private struct Arrow: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = pointsLeft ? rect.minX : rect.maxX
        let base = pointsLeft ? rect.maxX : rect.minX
        path.move(to: CGPoint(x: tip, y: rect.midY))
        path.addLine(to: CGPoint(x: base, y: rect.minY))
        path.addLine(to: CGPoint(x: base, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// "<" or ">" as two strokes.
private struct Chevron: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = pointsLeft ? rect.minX : rect.maxX
        let back = pointsLeft ? rect.maxX : rect.minX
        path.move(to: CGPoint(x: back, y: rect.minY))
        path.addLine(to: CGPoint(x: tip, y: rect.midY))
        path.addLine(to: CGPoint(x: back, y: rect.maxY))
        return path
    }
}
