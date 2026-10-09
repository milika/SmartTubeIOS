import SwiftUI

/// The DW-5000C face on its canvas (see CasioDW5000C for where the numbers come from). Printed
/// labels fill the ink boxes measured on the photo.
struct DW5000CFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioDW5000C.lcd }
    /// The case extension: the recess, red line and bricks grow by it, the LCD window by half;
    /// side labels and the groups below move down to share the space.
    private var e: CGFloat { CasioDW5000C.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            faceAndBricks
            topPrint
            sideLabels
            lcd.offset(y: e / 4)
            bottomPrint.offset(y: e)
        }
    }

    // MARK: Face, red line, bricks

    private var faceAndBricks: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 70, height: 70), radius: 30)
                .fill(CasioDW5000C.recess)
                .frame(width: 525, height: 440 + e)
                .offset(x: 48.5, y: 35)
            // Light mortar between dark bricks, inside the red line.
            ZStack(alignment: .topLeading) {
                CasioDW5000C.mortar
                BrickPattern(brick: CGSize(width: 19.2, height: 7.1), pitch: CGSize(width: 20.5, height: 8.417))
                    .fill(CasioDW5000C.brick)
                    .frame(width: 420, height: 330 + e)
                    .offset(x: 105.4 - 113.5, y: 102 - 103)
            }
            .frame(width: 397, height: 310.5 + e)
            .clipped()
            .mask(CutCornerRect(cut: CGSize(width: 54, height: 58), radius: 10))
            .offset(x: 113.5, y: 103)
            CutCornerRect(cut: CGSize(width: 61, height: 65), radius: 14)
                .stroke(CasioDW5000C.red, lineWidth: 6.5)
                .frame(width: 416.5, height: 329 + e)
                .offset(x: 102.75, y: 93.75)
        }
    }

    // MARK: Printed text

    private func ink(_ text: String, _ font: String, tracking: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, tracking: tracking)
    }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", "Michroma-Regular", tracking: 0.02)
                .placed(in: CGRect(x: 181.5, y: 63.5, width: 100, height: 18), color: CasioDW5000C.printWhite, bold: 0.7)
            ink("Lithium", "Saira-Medium")
                .placed(in: CGRect(x: 305, y: 66.5, width: 66.5, height: 14.5), color: CasioDW5000C.gold)
            BatteryMark()
                .fill(CasioDW5000C.gold)
                .frame(width: 57.5, height: 14.5)
                .offset(x: 394.5, y: 66.5)
            ShockResistBadge()
                .frame(width: 59, height: 40.5)
                .offset(x: 196.5, y: 109)
            ink("ALM. ON·OFF", "Michroma-Regular")
                .placed(in: CGRect(x: 336.5, y: 114.5, width: 100.5, height: 10.5), color: CasioDW5000C.labelWhite, bold: 0.3)
            pointer(x: 444.5, y: 115.5, width: 17.5, height: 8.5)
            ink("LAP·RESET/REPEAT", "Michroma-Regular")
                .placed(in: CGRect(x: 288.5, y: 132.5, width: 148, height: 10), color: CasioDW5000C.labelWhite, bold: 0.3)
            pointer(x: 444.5, y: 133, width: 18, height: 9.5)
        }
    }

    private func pointer(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Pointer(left: false).fill(CasioDW5000C.labelWhite).frame(width: width, height: height).offset(x: x, y: y)
    }

    /// ADJUST / MODE on the left (read upwards), LIGHT / 24HR on the right (read downwards), each
    /// with a dot by its button.
    private var sideLabels: some View {
        ZStack(alignment: .topLeading) {
            Group {
                vertical("ADJUST", CGRect(x: 80.5, y: 187, width: 10.5, height: 56.5), angle: -90)
                dot(x: 86, y: 175.25)
                vertical("LIGHT", CGRect(x: 530.5, y: 188, width: 10, height: 40), angle: 90)
                dot(x: 535.75, y: 176.5)
            }
            .offset(y: e / 4)
            Group {
                vertical("MODE", CGRect(x: 80.5, y: 286.5, width: 11, height: 42.5), angle: -90)
                dot(x: 86, y: 340)
                vertical("24HR", CGRect(x: 530, y: 292, width: 10, height: 37.5), angle: 90)
                dot(x: 535.25, y: 341)
            }
            .offset(y: 3 * e / 4)
        }
    }

    private func vertical(_ text: String, _ box: CGRect, angle: Double) -> some View {
        ink(text, "Michroma-Regular").placed(vertical: box, angle: angle, color: CasioDW5000C.labelWhite, bold: 0.3)
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioDW5000C.labelWhite).frame(width: 9, height: 9).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("WATER RESIST", "ArchivoExpanded-Black")
                .placed(in: CGRect(x: 148, y: 371, width: 178.5, height: 12.5), color: CasioDW5000C.teal)
            ink("200M", "ArchivoExpanded-Black")
                .placed(in: CGRect(x: 186, y: 390.5, width: 103.5, height: 17.5), color: CasioDW5000C.teal)
            ink("START·STOP", "Michroma-Regular")
                .placed(in: CGRect(x: 342.5, y: 374, width: 93.5, height: 10), color: CasioDW5000C.labelWhite, bold: 0.3)
            pointer(x: 443.5, y: 375, width: 17, height: 9)
            ink("SIG. ON·OFF", "Michroma-Regular")
                .placed(in: CGRect(x: 342.5, y: 392, width: 93, height: 9.5), color: CasioDW5000C.labelWhite, bold: 0.3)
            pointer(x: 443.5, y: 392.5, width: 17, height: 9)
            ink("JAPAN S", "Michroma-Regular")
                .placed(in: CGRect(x: 375, y: 406.5, width: 35, height: 5), color: CasioDW5000C.labelWhite)
            ink("ALARM CHRONOGRAPH", "Saira-Medium")
                .placed(in: CGRect(x: 197.5, y: 436, width: 224, height: 14), color: CasioDW5000C.gold)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        return ZStack(alignment: .topLeading) {
            LCDWindow(
                frame: CGRect(x: 145.5, y: 157, width: 330.5, height: 203.5 + e / 2), frameRadius: 10,
                surround: Color(white: 0.08), outline: CasioDW5000C.silver, outlineWidth: 6.5,
                glass: CGRect(x: 152, y: 163.5, width: 317.5, height: 190.5 + e / 2), glassRadius: 4,
                backlit: context.backlit, style: style)
            ZStack(alignment: .topLeading) {
                LCDText(
                    text: parts.weekday, font: style.letters, glyph: 36, edge: .leading(173), baseline: 218.5,
                    // The DW-5000C's W is double width; DSEG's is not. Wide enough for WE, not too wide for FR.
                    tracking: 10, style: style)
                if let marker = parts.marker {
                    ink(marker, "Michroma-Regular")
                        .placed(
                            in: CGRect(x: 228.5, y: 235.5, width: marker == "24H" ? 41 : 28, height: 15.5),
                            color: style.ink, bold: 0.6)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(style.ink, lineWidth: 2)
                    .frame(width: 158, height: 63.5)
                    .offset(x: 299, y: 176)
                LCDText(
                    text: Self.dateText(context.date, calendar: context.calendar, blank: style.digits.blankDigit),
                    font: style.digits, glyph: 44, edge: .trailing(456), baseline: 230.5, xScale: 0.877, style: style)
                LiveHoursMinutes(
                    context: context, font: style.digits, glyph: 74.5, trailing: 378, baseline: 335.5, xScale: 0.83,
                    colonGap: 9.5, style: style)
                LiveSeconds(
                    context: context, glyph: 53, trailing: 461, baseline: 335.5, xScale: 0.83, style: style)
            }
            .lcdSegmentShadow(style)
            .offset(y: e / 4)
        }
    }

    /// Month first, as on the DW-5000C ("11- 4", " 6-28"), each number right-aligned in two digits.
    static func dateText(_ date: Date, calendar: Calendar, blank: String) -> String {
        let c = calendar.dateComponents([.day, .month], from: date)
        return DisplayParts.twoCells(c.month ?? 1, blank: blank) + "-" + DisplayParts.twoCells(c.day ?? 1, blank: blank)
    }
}

/// The lithium-battery mark: four bars, a dot, four bars.
private struct BatteryMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = r.width / 57.5
        let bars: [CGFloat] = [1.8, 7.6, 13.0, 18.8, 38.4, 44.25, 50.1, 55.9]
        for x in bars {
            p.addRoundedRect(
                in: CGRect(x: r.minX + (x - 1.6) * s, y: r.minY, width: 3.2 * s, height: r.height),
                cornerSize: CGSize(width: 1.4 * s, height: 1.4 * s))
        }
        p.addEllipse(in: CGRect(x: r.minX + (28.8 - 5.9) * s, y: r.midY - 5.9 * s, width: 11.8 * s, height: 11.8 * s))
        return p
    }
}

/// The SHOCK RESIST badge: a gold shield outline (cut top corners, a point at the bottom), the two
/// words and a gold triangle.
private struct ShockResistBadge: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Shield().stroke(CasioDW5000C.gold, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .padding(1.25)
            InkText(text: "SHOCK", font: "Michroma-Regular")
                .placed(in: CGRect(x: 5.5, y: 5.5, width: 47.5, height: 7), color: CasioDW5000C.gold, bold: 0.4)
            InkText(text: "RESIST", font: "Michroma-Regular")
                .placed(in: CGRect(x: 5.5, y: 14, width: 48, height: 7), color: CasioDW5000C.gold, bold: 0.4)
            Triangle().fill(CasioDW5000C.gold)
                .frame(width: 41.5, height: 11)
                .offset(x: 8.5, y: 24.5)
        }
    }

    private struct Shield: Shape {
        func path(in r: CGRect) -> Path {
            let c: CGFloat = 4.5
            var p = Path()
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.64))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.64))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.closeSubpath()
            return p
        }
    }

    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}
