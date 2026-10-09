import SwiftUI

/// The A158W face on its canvas (see CasioA158W for where the numbers come from).
struct A158WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioA158W.lcd }
    /// The case extension: plate and lines grow by it, the LCD window by half, and the groups
    /// below move down to share the space evenly.
    private var extra: CGFloat { CasioA158W.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plate
            topPrint
            lcd.offset(y: extra / 4)
            bottomPrint.offset(y: extra)
        }
    }

    // MARK: Plate and octagon lines

    private var plate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 60, height: 75), bottomCut: CGSize(width: 45, height: 45), radius: 20)
                .fill(CasioA158W.plate)
                .frame(width: 544.5, height: 453 + extra)
                .offset(x: 33, y: 22.5)
            CutCornerRect(cut: CGSize(width: 52, height: 66), bottomCut: CGSize(width: 38, height: 38), radius: 16)
                .stroke(CasioA158W.line, lineWidth: 1.5)
                .frame(width: 514.5, height: 423 + extra)
                .offset(x: 48, y: 37.5)
            CutCornerRect(cut: CGSize(width: 42, height: 55), bottomCut: CGSize(width: 30, height: 30), radius: 14)
                .stroke(CasioA158W.blue, lineWidth: 8)
                .frame(width: 480, height: 387 + extra)
                .offset(x: 65.25, y: 59.25)
        }
    }

    // MARK: Printed text

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            Text("CASIO")
                .font(CasioA158W.michroma(23))
                .tracking(1)
                .foregroundStyle(CasioA158W.printWhite)
                .emboldened(1.4)
                .place(centerX: 191.5, centerY: 88.75)
            Text("ALARM CHRONO")
                .font(CasioA158W.saira(22))
                .tracking(1.5)
                .foregroundStyle(CasioA158W.gold)
                .emboldened(0.4)
                .place(leading: 278.5, centerY: 85.25, width: 220)
            Rectangle().fill(CasioA158W.line).frame(width: 408, height: 2).offset(x: 94.5, y: 105.5)

            // ▬ LIGHT / LAP · RESET   ▬ MODE        Lithium   START · STOP / 12 · 24H ▬
            marker(x: 100.5, centerY: 132)
            marker(x: 100.5, centerY: 150)
            label("LIGHT / LAP · RESET", leading: 127.5, centerY: 131.5, tracking: 0.9)
            label("MODE", leading: 127.5, centerY: 149.5, tracking: 0.9)
            Text("Lithium")
                .font(CasioA158W.saira(14.5))
                .foregroundStyle(CasioA158W.paleGold)
                .place(trailing: 450.5, centerY: 127.25, width: 120)
            Text("START · STOP / 12 · 24H")
                .font(CasioA158W.saira(14.3))
                .tracking(0.9)
                .foregroundStyle(CasioA158W.printWhite)
                .place(trailing: 474, centerY: 147, width: 220)
            marker(x: 480, centerY: 147)
        }
    }

    private func label(_ text: String, leading: CGFloat, centerY: CGFloat, tracking: CGFloat) -> some View {
        Text(text)
            .font(CasioA158W.saira(14.3))
            .tracking(tracking)
            .foregroundStyle(CasioA158W.printWhite)
            .place(leading: leading, centerY: centerY, width: 220)
    }

    /// The small dark-red dashes beside the button labels.
    private func marker(x: CGFloat, centerY: CGFloat) -> some View {
        Rectangle().fill(CasioA158W.marker).frame(width: 16.5, height: 4.5).offset(x: x, y: centerY - 2.25)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(CasioA158W.line).frame(width: 423, height: 2).offset(x: 90, y: 386)
            // WATER RESIST on a steel-blue band whose right end is slanted.
            Slant().fill(CasioA158W.band).frame(width: 272.5, height: 27).offset(x: 112.5, y: 400.5)
            Text("WATER RESIST")
                .font(CasioA158W.michroma(16.8))
                .tracking(2)
                .foregroundStyle(CasioA158W.gold)
                .emboldened(0.8)
                .place(leading: 147.5, centerY: 414.25, width: 240)
            Text("WR")
                .font(CasioA158W.sairaExpanded(25.6))
                .foregroundStyle(CasioA158W.maroon)
                .oblique()
                .scaleEffect(x: 1.77, y: 1)
                .place(centerX: 436.25, centerY: 414.75)
        }
    }

    // MARK: LCD (module 593, like the F-91W)

    private var lcd: some View {
        let glass = CGRect(x: 117, y: 177, width: 370.5, height: 175.5 + extra / 2)
        // The A158W's window shows the LCD 9.5 pt lower than the F-91W's (measured).
        return LCDPanel(
            display: Module593Display.self, frame: CGRect(x: 105, y: 168, width: 390, height: 195 + extra / 2),
            frameRadius: 14, outline: CasioA158W.line, outlineWidth: 1.5, glass: glass, glassRadius: 6,
            displayShift: 9.5, context: context, style: style)
    }
}

/// A rectangle whose right end slants (wider at the bottom), like the A158W's WATER RESIST band.
private struct Slant: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let slant = rect.height * 0.37
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
