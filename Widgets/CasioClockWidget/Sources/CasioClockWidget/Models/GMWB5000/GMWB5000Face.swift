import SwiftUI

/// The GMW-B5000 face on its canvas (see CasioGMWB5000 for where the numbers come from).
struct GMWB5000Face: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioGMWB5000.lcd }
    /// The case extension: bezel, plate and frame lines grow by it, the LCD window by half; side
    /// labels and the groups below move down to share the space.
    private var e: CGFloat { CasioGMWB5000.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bezelAndPlate
            topPrint
            sideLabels
            lcd.offset(y: e / 4)
            bottomPrint.offset(y: e)
        }
    }

    // MARK: Bezel, plate, bricks

    private var bezelAndPlate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: Self.bezelCut, bottomCut: Self.bezelBottomCut, radius: 45)
                .fill(CasioGMWB5000.steel)
                .overlay(
                    CutCornerRect(cut: Self.bezelCut, bottomCut: Self.bezelBottomCut, radius: 45)
                        .stroke(CasioGMWB5000.steelEdge, lineWidth: 1.5))
                .frame(width: 569, height: 526 + e)
                .offset(x: 18, y: 19)
            engraved("PROTECTION", size: 23.6, tracking: 6.3).place(centerX: 308.5, centerY: 59.25)
            // Polished bevel, black plate.
            RoundedRectangle(cornerRadius: 62, style: .continuous)
                .fill(CasioGMWB5000.bevel)
                .frame(width: 461, height: 395 + e)
                .offset(x: 76, y: 82)
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(CasioGMWB5000.plate)
                .frame(width: 451, height: 383 + e)
                .offset(x: 81, y: 87)
            // Brick pattern inside the grey line.
            BrickPattern(brick: CGSize(width: 16, height: 4.6), pitch: CGSize(width: 18.8, height: 7.75))
                .fill(CasioGMWB5000.brick)
                .frame(width: 384, height: 317 + e)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .offset(x: 116, y: 121)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(CasioGMWB5000.frameLine, lineWidth: 3)
                .frame(width: 384, height: 317 + e)
                .offset(x: 116, y: 121)
            engraved("G-SHOCK", size: 34.6, tracking: 6.5).place(centerX: 305.75, centerY: 499 + e)
        }
    }

    /// Letters engraved in the steel: light letters with a darker edge.
    private func engraved(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        ZStack {
            Text(text).font(CasioGMWB5000.michroma(size)).tracking(tracking)
                .foregroundStyle(CasioGMWB5000.engraveShadow).emboldened(1.1)
            Text(text).font(CasioGMWB5000.michroma(size)).tracking(tracking)
                .foregroundStyle(Color(white: 0.95)).emboldened(0.3)
        }
    }

    static let bezelCut = CGSize(width: 78, height: 86)
    static let bezelBottomCut = CGSize(width: 80, height: 90)

    // MARK: Printed text

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            Text("CASIO")
                .font(CasioGMWB5000.michroma(15.2))
                .tracking(2.6)
                .foregroundStyle(CasioGMWB5000.printWhite)
                .emboldened(0.6)
                .place(leading: 188, centerY: 104.25, width: 100)
            Text("TOUGH SOLAR")
                .font(CasioGMWB5000.michroma(12.4))
                .tracking(1.6)
                .foregroundStyle(CasioGMWB5000.printGrey)
                .place(leading: 278.5, centerY: 106.25, width: 180)
            ShockResistBadge()
                .frame(width: 53.5, height: 30)
                .offset(x: 195, y: 130)
            Pointer(left: true).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 334, y: 144.5)
            label("SPLIT·RESET", trailing: 440, centerY: 144.5, tracking: 0.25)
            label("LIGHT", trailing: 426, centerY: 160.25, tracking: -0.4)
            Pointer(left: false).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 436, y: 160.75)
        }
    }

    private func label(
        _ text: String, leading: CGFloat? = nil, trailing: CGFloat? = nil, centerY: CGFloat, tracking: CGFloat = 0.8
    ) -> some View {
        let t = Text(text)
            .font(CasioGMWB5000.michroma(9.9))
            .tracking(tracking)
            .foregroundStyle(CasioGMWB5000.labelGrey)
            .emboldened(0.25)
        return Group {
            if let leading {
                t.place(leading: leading, centerY: centerY, width: 200)
            } else if let trailing {
                t.place(trailing: trailing, centerY: centerY, width: 200)
            }
        }
    }

    /// ADJUST / MODE on the left (read upwards), SET [–] / SET [+] on the right (read downwards),
    /// each with a dot by its button.
    private var sideLabels: some View {
        ZStack(alignment: .topLeading) {
            vertical("ADJUST", centerX: 99.75, centerY: 233.75 + e / 4, angle: -90, tracking: 0.5)
            dot(x: 98.5, y: 190 + e / 4)
            vertical("MODE", centerX: 98.5, centerY: 330.5 + 3 * e / 4, angle: -90, tracking: 1.4)
            dot(x: 98.5, y: 365 + 3 * e / 4)
            vertical("SET [–]", centerX: 516.5, centerY: 227.75 + e / 4, angle: 90, tracking: 3.75)
            dot(x: 516.5, y: 190 + e / 4)
            vertical("SET [+]", centerX: 516, centerY: 335 + 3 * e / 4, angle: 90, tracking: 2.8)
            dot(x: 516.5, y: 368 + 3 * e / 4)
        }
    }

    private func vertical(_ text: String, centerX: CGFloat, centerY: CGFloat, angle: Double, tracking: CGFloat)
        -> some View
    {
        Text(text)
            .font(CasioGMWB5000.michroma(9.7))
            .tracking(tracking)
            .foregroundStyle(CasioGMWB5000.labelGrey)
            .emboldened(0.25)
            .fixedSize()
            .rotationEffect(.degrees(angle))
            .position(x: centerX, y: centerY)
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioGMWB5000.printWhite).frame(width: 5.5, height: 5.5).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            label("WATER RESIST", leading: 172, centerY: 400, tracking: 3.4)
            label("20BAR", leading: 212, centerY: 415.25, tracking: 4)
            label("RECEIVING", trailing: 426.5, centerY: 400, tracking: 0.5)
            Pointer(left: false).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 436, y: 399.5)
            label("START·STOP", trailing: 426.5, centerY: 416.5, tracking: 0)
            Pointer(left: false).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 436, y: 415)
            Text("Bluetooth")
                .font(CasioGMWB5000.saira(19.6))
                .foregroundStyle(CasioGMWB5000.printWhite)
                .scaleEffect(x: 0.82, y: 1, anchor: .leading)
                .place(leading: 186.5, centerY: 453.75, width: 120)
            Text("MULTI BAND 6")
                .font(CasioGMWB5000.michroma(11.5))
                .tracking(1.1)
                .foregroundStyle(CasioGMWB5000.printWhite)
                .place(leading: 283.5, centerY: 456.75, width: 200)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let parts = DisplayParts.make(
            for: context.date, calendar: context.calendar, twelveHour: context.uses12HourClock,
            blankDigit: style.digits.blankDigit)
        return ZStack(alignment: .topLeading) {
            LCDWindow(
                frame: CGRect(x: 147, y: 172, width: 321, height: 215 + e / 2), frameRadius: 18,
                surround: CasioGMWB5000.surround, outline: CasioGMWB5000.surround, outlineWidth: 0,
                glass: CGRect(x: 151, y: 176, width: 313, height: 207 + e / 2), glassRadius: 14,
                backlit: context.backlit, style: style)
            ZStack(alignment: .topLeading) {
                indicator("PS", leading: 178, centerY: 197.75, tracking: 5.3)
                indicator("RCVD", leading: 250, centerY: 198.25)
                if context.calendar.timeZone.isDaylightSavingTime(for: context.date) {
                    indicator("DST", leading: 197, centerY: 270.75, tracking: 3.1)
                }
                // P for PM on a 12-hour clock (the G-Shock shows nothing on a 24-hour clock).
                if parts.isPM {
                    indicator("P", leading: 161, centerY: 304)
                }
                LCDText(
                    text: parts.weekday, font: style.letters, glyph: 41.5, edge: .leading(227), baseline: 251.5,
                    tracking: 2, style: style)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(style.ink, lineWidth: 1.6)
                    .frame(width: 136, height: 61)
                    .offset(x: 311, y: 201)
                DotMatrixText(
                    text: Self.dateText(context.date, calendar: context.calendar, dayFirst: Self.localeDayFirst),
                    pitch: CGSize(width: 4, height: 5.7), dot: CGSize(width: 3.3, height: 4.8), advance: 27.25,
                    narrowAdvance: 14, color: style.ink
                )
                .frame(width: 130, height: 40, alignment: .topLeading)
                .offset(x: 323.75, y: 211)
                LiveHoursMinutes(
                    context: context, font: style.digits, glyph: 76, trailing: 372, baseline: 362.5, xScale: 0.85,
                    style: style)
                LiveSeconds(
                    date: context.date, calendar: context.calendar, previewSeconds: context.previewSeconds,
                    glyph: 50, trailing: 450, baseline: 360.5, xScale: 0.93, style: style)
            }
            .offset(y: e / 4)
        }
    }

    private func indicator(_ text: String, leading: CGFloat, centerY: CGFloat, tracking: CGFloat = 1) -> some View {
        Text(text)
            .font(CasioGMWB5000.michroma(14.4))
            .tracking(tracking)
            .foregroundStyle(style.ink)
            .emboldened(0.5)
            .scaleEffect(x: 0.82, y: 1, anchor: .leading)
            .place(leading: leading, centerY: centerY, width: 60)
    }

    // MARK: Date

    /// Day first ("28. 6") unless the locale writes the month first (" 6-28"), like the watch's
    /// date-format setting.
    static func dateText(_ date: Date, calendar: Calendar, dayFirst: Bool) -> String {
        let c = calendar.dateComponents([.day, .month], from: date)
        func two(_ n: Int) -> String { n < 10 ? " \(n)" : "\(n)" }
        let day = two(c.day ?? 1), month = two(c.month ?? 1)
        return dayFirst ? day + "." + month : month + "-" + day
    }

    static var localeDayFirst: Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: .current) ?? "d.M"
        guard let d = f.firstIndex(of: "d"), let m = f.firstIndex(of: "M") else { return true }
        return d < m
    }
}

/// The SHOCK RESIST shield: cut top corners, straight sides, a point at the bottom.
private struct ShockResistBadge: View {
    var body: some View {
        ZStack {
            Shield().fill(CasioGMWB5000.plate)
            Shield().stroke(CasioGMWB5000.printGrey, lineWidth: 1.4)
            VStack(spacing: 0) {
                Text("SHOCK")
                Text("RESIST")
            }
            .font(CasioGMWB5000.michroma(6.6))
            .foregroundStyle(CasioGMWB5000.printGrey)
            .offset(y: -3)
        }
    }

    private struct Shield: Shape {
        func path(in r: CGRect) -> Path {
            let c = r.width * 0.12
            var p = Path()
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.62))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.closeSubpath()
            return p
        }
    }
}
