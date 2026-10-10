import SwiftUI

/// The AE-1200WH face on its canvas (see CasioAE1200WH for where the numbers come from): the
/// silver case with its bands and buttons, the bezel, the plate's print and its four LCD windows.
struct AE1200WHFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioAE1200WH.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            straps
            caseShape
            bandPrint
            bezelAndPlate
            windows
            dial
            platePrint
        }
    }

    // MARK: Case

    private var straps: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(CasioAE1200WH.strap).frame(width: 290, height: 52).offset(x: 205, y: 0)
            Rectangle().fill(CasioAE1200WH.strap).frame(width: 290, height: 24).offset(x: 205, y: 656)
        }
    }

    /// Buttons behind the case, two each side.
    private static let buttons = [
        CGRect(x: 20, y: 215, width: 22, height: 62), CGRect(x: 20, y: 428, width: 22, height: 62),
        CGRect(x: 638, y: 213, width: 22, height: 62), CGRect(x: 638, y: 428, width: 22, height: 62),
    ]

    private var caseShape: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.buttons.enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 5).fill(CasioAE1200WH.chrome)
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            }
            Polygon(points: Self.caseOutline).fill(CasioAE1200WH.silverSide)
            // The bands (top and bottom) catch more light than the sides.
            Polygon(points: Self.topBand).fill(CasioAE1200WH.silver)
            Polygon(points: Self.bottomBand).fill(CasioAE1200WH.silver)
            Rectangle().fill(CasioAE1200WH.strap).frame(width: 288, height: 16).offset(x: 206, y: 34)
            Rectangle().fill(CasioAE1200WH.strap).frame(width: 288, height: 19).offset(x: 206, y: 657)
            ForEach(Array(Self.screws.enumerated()), id: \.offset) { _, center in
                screw(at: center)
            }
        }
    }

    /// The case outline, clockwise from the top left (image canvas points).
    private static let caseOutline: [CGPoint] = [
        (176.5, 33), (552, 33), (556, 60), (560, 100), (564, 120), (581, 140), (598, 160), (611, 180), (621, 194),
        (641, 214), (642, 290), (632, 305), (623, 310), (623, 392), (641, 410), (642, 490), (634, 500),
        (612.5, 520), (602.5, 540), (586, 560), (568, 580), (564, 600), (562, 620), (560.5, 640), (558, 676),
        (161.5, 676), (151.5, 660), (140, 640), (129.5, 620), (119, 600), (106.5, 580), (89.5, 560), (72.5, 540),
        (61.5, 520), (52, 506), (37, 492), (37, 410), (52, 395), (52, 310), (37, 295), (37, 213), (54, 197),
        (65.5, 180), (78.5, 160), (95.5, 140), (112.5, 120), (124, 100), (135, 80), (146.5, 60), (160, 40),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private static let topBand: [CGPoint] = [
        (176.5, 33), (552, 33), (556, 60), (560, 100), (564, 108), (150, 108), (160, 40),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private static let bottomBand: [CGPoint] = [
        (148, 595), (566, 595), (562, 620), (560.5, 640), (558, 676), (161.5, 676), (151.5, 660), (140, 640),
        (129.5, 620), (119, 600),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private static let screws = [
        CGPoint(x: 196, y: 78), CGPoint(x: 467.5, y: 78), CGPoint(x: 194.5, y: 626), CGPoint(x: 466.5, y: 626),
    ]

    private func screw(at center: CGPoint) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.62))
            Circle().strokeBorder(Color(white: 0.45), lineWidth: 2)
            Circle().fill(Color(white: 0.80)).frame(width: 18, height: 18)
            Circle().strokeBorder(Color(white: 0.5), lineWidth: 1.5).frame(width: 18, height: 18)
        }
        .frame(width: 30, height: 28)
        .offset(x: center.x - 15, y: center.y - 14)
    }

    private var bandPrint: some View {
        ZStack(alignment: .topLeading) {
            InkText(text: "WORLD", font: CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 236, y: 75, width: 106.5, height: 15.5), color: CasioAE1200WH.caseInk)
            InkText(text: "TIME", font: CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 360, y: 74.5, width: 71, height: 15.5), color: CasioAE1200WH.caseInk)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 232, y: 613.5, width: 199, height: 16.5), color: CasioAE1200WH.caseInk)
        }
    }

    // MARK: Bezel and plate

    private static let bezelOutline: [CGPoint] = [
        (150, 108.5), (508, 108.5), (588, 196), (588, 505), (520, 594.5), (148, 594.5), (72, 503), (72, 198),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private static let slopeOutline: [CGPoint] = [
        (162, 140), (497, 140), (556, 200), (556, 495), (500, 562), (160, 562), (100, 495), (100, 202),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// The plate's grey border line (its bottom edge is hidden under the bezel's slope).
    private static let plateLine: [CGPoint] = [
        (166, 543), (119.5, 487), (119.5, 207), (170, 157.5), (490, 157.5), (535, 205), (535, 487), (490, 543),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private var bezelAndPlate: some View {
        ZStack(alignment: .topLeading) {
            Polygon(points: Self.bezelOutline).fill(CasioAE1200WH.bezel)
            Polygon(points: Self.slopeOutline).fill(CasioAE1200WH.bezelSlope)
            Polygon(points: Self.plateLine).fill(CasioAE1200WH.plate)
            Polygon(points: Self.plateLine, closed: false).stroke(CasioAE1200WH.plateLine, lineWidth: 2.5)
        }
    }

    // MARK: Dial

    private var dial: some View {
        let ring = AE1200WHDialDisplay.center
        let window = AE1200WHDialDisplay.window
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(CasioAE1200WH.dialHousing)
                .frame(width: 172, height: 172).offset(x: ring.x - 86, y: ring.y - 86)
            ForEach(Array(Self.dialScrews.enumerated()), id: \.offset) { _, offset in
                Circle().strokeBorder(Color(white: 0.30), lineWidth: 2).frame(width: 11, height: 11)
                    .offset(x: ring.x + offset.x - 5.5, y: ring.y + offset.y - 5.5)
            }
            Circle().fill(CasioAE1200WH.dialRing).frame(width: 182, height: 182).offset(x: ring.x - 91, y: ring.y - 91)
            // One shape each for the ticks and the numerals: as separate rotated views they made the
            // widget's timeline archive too large for WidgetKit (over 10 MB).
            DialTicks(center: ring).fill(CasioAE1200WH.print)
            DialNumerals().fill(CasioAE1200WH.print)
            DialNumerals().stroke(CasioAE1200WH.print, style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
            LCDPanel(
                display: AE1200WHDialDisplay.self,
                frame: CGRect(x: window.x - 65, y: window.y - 65, width: 130, height: 130), frameRadius: 65,
                surround: CasioAE1200WH.windowRim, outline: .clear, outlineWidth: 0,
                glass: CGRect(x: window.x - 63, y: window.y - 63, width: 126, height: 126), glassRadius: 63,
                context: context, style: style)
        }
    }

    private static let dialScrews = [
        CGPoint(x: -76, y: -72), CGPoint(x: 70, y: -72), CGPoint(x: -76, y: 72), CGPoint(x: 70, y: 72),
    ]

    // MARK: Windows

    private var windows: some View {
        ZStack(alignment: .topLeading) {
            window(AE1200WHIndicatorDisplay.self, CGRect(x: 344.5, y: 204.5, width: 153.5, height: 38))
            window(AE1200WHMapDisplay.self, CGRect(x: 344.5, y: 259.5, width: 153.5, height: 85.5))
            window(AE1200WHDisplay.self, CGRect(x: 163.5, y: 362, width: 334, height: 141.5))
            MainWindowCorner().fill(CasioAE1200WH.plate)
        }
    }

    private func window<Display: LCDModuleDisplay>(_ display: Display.Type, _ glass: CGRect) -> some View {
        LCDPanel(
            display: display, frame: glass.insetBy(dx: -2, dy: -2), frameRadius: 10,
            surround: CasioAE1200WH.windowRim, outline: .clear, outlineWidth: 0, glass: glass, glassRadius: 8,
            context: context, style: style)
    }

    // MARK: Plate print

    private func ink(
        _ text: String, _ box: CGRect, _ color: Color, bold: CGFloat = 0.5, barBold: CGFloat? = nil
    )
        -> some View
    {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: color, bold: bold, barBold: barBold)
    }

    private var platePrint: some View {
        ZStack(alignment: .topLeading) {
            ink("5", CGRect(x: 194, y: 171, width: 13, height: 11), CasioAE1200WH.print)
            ink("ALARMS", CGRect(x: 211, y: 170, width: 96.5, height: 11.5), CasioAE1200WH.print)
            ink(
                "CASIO", CGRect(x: 368, y: 171.5, width: 94, height: 18), CasioAE1200WH.printBright, bold: 1.2,
                barBold: 0.75)
            ink("WR100M", CGRect(x: 185, y: 382, width: 98, height: 11.5), CasioAE1200WH.print)
            ink("10", CGRect(x: 233.5, y: 521.5, width: 23, height: 15), CasioAE1200WH.printBright)
            ink("YEAR", CGRect(x: 261, y: 522, width: 55.5, height: 14.5), CasioAE1200WH.printBright)
            ink("BATTERY", CGRect(x: 327.5, y: 522, width: 93, height: 14.5), CasioAE1200WH.printBright)
            InkText(text: "ADJUST", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 129.5, y: 252.5, width: 8.5, height: 88), angle: -90,
                    color: CasioAE1200WH.printSide, bold: 0.5)
            InkText(text: "MODE", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 135, y: 411, width: 9.5, height: 66), angle: -90,
                    color: CasioAE1200WH.printSide, bold: 0.5)
            InkText(text: "LIGHT", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 512.5, y: 223.5, width: 9.5, height: 68.5), angle: 90,
                    color: CasioAE1200WH.printSide, bold: 0.5)
            InkText(text: "SEARCH", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 513, y: 380, width: 9.5, height: 97), angle: 90,
                    color: CasioAE1200WH.printSide, bold: 0.5)
        }
    }
}

/// The dial ring's minute ticks: longer and wider every five minutes, a square at the quarters.
private struct DialTicks: Shape {
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for minute in 0..<60 {
            let quarter = minute % 15 == 0
            let five = minute % 5 == 0
            let width: CGFloat = quarter ? 5 : (five ? 2.5 : 1.5)
            let inner: CGFloat = five ? 69 : 70.5
            let outer: CGFloat = five ? 76 : 74.5
            let tick = Path(CGRect(x: -width / 2, y: -outer, width: width, height: outer - inner))
            let turn = CGAffineTransform(rotationAngle: CGFloat(minute) * .pi / 30)
                .concatenating(CGAffineTransform(translationX: rect.minX + center.x, y: rect.minY + center.y))
            path.addPath(tick, transform: turn)
        }
        return path
    }
}

/// 60, 05, 10 … 55 around the dial's ring, each at its measured centre and upright width (narrower
/// with a 1), 8.5 pt tall less the 0.4 pt the stroke adds; upright in the upper half, turned to
/// read in the lower.
private struct DialNumerals: Shape {
    private static let numerals: [(center: CGPoint, width: CGFloat)] = [
        (233.25, 201, 20.5), (273.75, 211.25, 20.5), (305.25, 241, 17), (316.5, 283, 17), (304.5, 324.5, 20.5),
        (275, 354.75, 20.5), (234, 366.25, 20.5), (193.5, 354.25, 20.5), (164.75, 323.75, 20.5),
        (153.75, 282.25, 20.5), (164.25, 241.25, 20.5), (193.5, 211.75, 20.5),
    ].map { (CGPoint(x: $0.0, y: $0.1), $0.2) }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, numeral) in Self.numerals.enumerated() {
            let angle = Double(index) * 30
            let text = index == 0 ? "60" : String(format: "%02d", index * 5)
            let turn = angle > 90 && angle < 270 ? angle - 180 : angle
            let width = numeral.width - 0.8
            let glyphs = InkText(text: text, font: CaseFont.michroma)
                .path(in: CGRect(x: -width / 2, y: -3.85, width: width, height: 7.7))
            let place = CGAffineTransform(rotationAngle: turn * .pi / 180)
                .concatenating(
                    CGAffineTransform(translationX: rect.minX + numeral.center.x, y: rect.minY + numeral.center.y))
            path.addPath(glyphs, transform: place)
        }
        return path
    }
}

/// The plate over the main window's upper-left corner, where the window steps down beside the
/// dial (WR100M sits on it).
private struct MainWindowCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 160, y: 360))
        path.addLine(to: CGPoint(x: 346, y: 360))
        path.addQuadCurve(to: CGPoint(x: 337, y: 367), control: CGPoint(x: 341, y: 362))
        path.addLine(to: CGPoint(x: 314, y: 398))
        path.addQuadCurve(to: CGPoint(x: 300, y: 408), control: CGPoint(x: 308, y: 407))
        path.addLine(to: CGPoint(x: 173.5, y: 408))
        path.addArc(
            center: CGPoint(x: 173.5, y: 418), radius: 10, startAngle: .degrees(-90), endAngle: .degrees(180),
            clockwise: true)
        path.addLine(to: CGPoint(x: 160, y: 418))
        path.closeSubpath()
        return path
    }
}

/// A closed (or open) polyline through canvas points.
private struct Polygon: Shape {
    let points: [CGPoint]
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(points)
        if closed { path.closeSubpath() }
        return path
    }
}
