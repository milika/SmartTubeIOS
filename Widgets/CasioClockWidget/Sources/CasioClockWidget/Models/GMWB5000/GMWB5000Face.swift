import SwiftUI

/// The GMW-B5000 face on its canvas (see CasioGMWB5000 for where the numbers come from).
struct GMWB5000Face: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioGMWB5000.lcd }
    /// The case extension: bezel, plate and frame lines grow by it, the LCD window by half; side
    /// labels and the groups below move down to share the space.
    private var stretch: CaseExtension { CaseExtension(amount: CasioGMWB5000.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bezelAndPlate
            topPrint
            sideLabels
            lcd.band(.display, of: stretch)
            bottomPrint.band(.bottom, of: stretch)
        }
    }

    // MARK: Bezel, plate, bricks

    private var bezelAndPlate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: Self.bezelCut, bottomCut: Self.bezelBottomCut, radius: 45)
                .fill(CasioGMWB5000.steel)
                .overlay(
                    CutCornerRect(cut: Self.bezelCut, bottomCut: Self.bezelBottomCut, radius: 45)
                        .stroke(CasioGMWB5000.steelEdge, lineWidth: 1.5)
                )
                .frame(width: 569, height: 526 + stretch.caseGrowth)
                .offset(x: 18, y: 19)
            engraved("PROTECTION", size: 23.6, tracking: 6.3).place(centerX: 308.5, centerY: 59.25)
            // Polished bevel, black plate.
            RoundedRectangle(cornerRadius: 62, style: .continuous)
                .fill(CasioGMWB5000.bevel)
                .frame(width: 461, height: 395 + stretch.caseGrowth)
                .offset(x: 76, y: 82)
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(CasioGMWB5000.plate)
                .frame(width: 451, height: 383 + stretch.caseGrowth)
                .offset(x: 81, y: 87)
            // Brick pattern inside the grey line.
            BrickPattern(brick: CGSize(width: 16, height: 4.6), pitch: CGSize(width: 18.8, height: 7.75))
                .fill(CasioGMWB5000.brick)
                .frame(width: 384, height: 317 + stretch.caseGrowth)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .offset(x: 116, y: 121)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(CasioGMWB5000.frameLine, lineWidth: 3)
                .frame(width: 384, height: 317 + stretch.caseGrowth)
                .offset(x: 116, y: 121)
            engraved("G-SHOCK", size: 34.6, tracking: 6.5).place(
                centerX: 305.75, centerY: 499 + stretch.offset(.bottom))
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
            // Ink boxes measured on the photo.
            InkText(text: "CASIO", font: CaseFont.michroma, tracking: 0.17)
                .placed(in: CGRect(x: 188, y: 98, width: 74.5, height: 13), color: CasioGMWB5000.printWhite, bold: 0.6)
            InkText(text: "TOUGH SOLAR", font: CaseFont.michroma, tracking: 0.13)
                .placed(in: CGRect(x: 279.5, y: 102.5, width: 146.5, height: 9.5), color: CasioGMWB5000.printGrey)
            ShockResistBadge()
                .frame(width: 53.5, height: 30)
                .offset(x: 195, y: 130)
            Pointer(left: true).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 334, y: 144.5)
            label("SPLIT·RESET", trailing: 440, centerY: 144.5, tracking: 0.25)
            InkText(text: "LIGHT", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 388.5, y: 156.5, width: 28, height: 8.5), color: CasioGMWB5000.labelGrey, bold: 0.25)
            Pointer(left: false).fill(CasioGMWB5000.printWhite).frame(width: 8, height: 9).position(x: 437.5, y: 160.75)
        }
    }

    private func label(
        _ text: String, leading: CGFloat? = nil, trailing: CGFloat? = nil, centerY: CGFloat, tracking: CGFloat = 0.8
    ) -> some View {
        let printed = Text(text)
            .font(CasioGMWB5000.michroma(9.9))
            .tracking(tracking)
            .foregroundStyle(CasioGMWB5000.labelGrey)
            .emboldened(0.25)
        return Group {
            if let leading {
                printed.place(leading: leading, centerY: centerY, width: 200)
            } else if let trailing {
                printed.place(trailing: trailing, centerY: centerY, width: 200)
            }
        }
    }

    /// ADJUST / MODE on the left (read upwards), SET [–] / SET [+] on the right (read downwards),
    /// each with a dot by its button.
    private var sideLabels: some View {
        ZStack(alignment: .topLeading) {
            vertical("ADJUST", centerX: 99.75, centerY: 233.75 + stretch.offset(.upperSides), angle: -90, tracking: 0.5)
            dot(x: 98.5, y: 190 + stretch.offset(.upperSides))
            vertical("MODE", centerX: 98.5, centerY: 330.5 + stretch.offset(.lowerSides), angle: -90, tracking: 1.4)
            dot(x: 98.5, y: 365 + stretch.offset(.lowerSides))
            InkText(text: "SET [–]", font: CaseFont.michroma, tracking: 0.39)
                .placed(
                    vertical: CGRect(x: 511.5, y: 205.5, width: 10.5, height: 56), angle: 90,
                    color: CasioGMWB5000.labelGrey, bold: 0.25
                )
                .offset(y: stretch.offset(.upperSides))
            dot(x: 516.5, y: 192.5 + stretch.offset(.upperSides))
            InkText(text: "SET [+]", font: CaseFont.michroma, tracking: 0.29)
                .placed(
                    vertical: CGRect(x: 511, y: 300, width: 10.5, height: 56), angle: 90,
                    color: CasioGMWB5000.labelGrey, bold: 0.25
                )
                .offset(y: stretch.offset(.lowerSides))
            dot(x: 516.5, y: 368 + stretch.offset(.lowerSides))
        }
    }

    private func vertical(
        _ text: String, centerX: CGFloat, centerY: CGFloat, angle: Double, tracking: CGFloat
    )
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
            InkText(text: "20BAR", font: CaseFont.michroma, tracking: 0.4)
                .placed(
                    in: CGRect(x: 206.5, y: 410.5, width: 73, height: 10), color: CasioGMWB5000.labelGrey, bold: 0.25)
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
        let glass = CGRect(x: 151, y: 176, width: 313, height: 207 + stretch.windowGrowth)
        return LCDPanel(
            display: Module3459Display.self,
            frame: CGRect(x: 147, y: 172, width: 321, height: 215 + stretch.windowGrowth),
            frameRadius: 18, surround: CasioGMWB5000.surround, outline: CasioGMWB5000.surround, outlineWidth: 0,
            glass: glass, glassRadius: 14, context: context, style: style)
    }
}

/// The SHOCK RESIST shield: cut top corners, straight sides, a point at the bottom.
private struct ShockResistBadge: View {
    /// This watch's proportions of the SHOCK RESIST shield.
    private static let shield = ShockResistShield(cornerFraction: 0.12, shoulder: 0.62)

    var body: some View {
        ZStack {
            Self.shield.fill(CasioGMWB5000.plate)
            Self.shield.stroke(CasioGMWB5000.printGrey, lineWidth: 1.4)
            VStack(spacing: 0) {
                Text("SHOCK")
                Text("RESIST")
            }
            .font(CasioGMWB5000.michroma(6.6))
            .foregroundStyle(CasioGMWB5000.printGrey)
            .offset(y: -3)
        }
    }

}
