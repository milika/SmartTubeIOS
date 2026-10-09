import SwiftUI

/// The F-91W face on its canvas (see CasioF91W for where the numbers come from).
struct F91WFace: View {
    let context: CasioFaceContext

    private var date: Date { context.date }
    private var calendar: Calendar { context.calendar }
    private var uses12HourClock: Bool { context.uses12HourClock }
    private var backlit: Bool { context.backlit }
    private var previewSeconds: Int? { context.previewSeconds }
    private var style: LCDStyle { CasioF91W.lcd }
    /// The case extension (see CasioF91W.caseExtension): the frame lines grow by it, the LCD
    /// window by half of it, and the groups below move down to share the space evenly.
    private var e: CGFloat { CasioF91W.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bezel
            printedFace
            lcd
        }
    }

    // MARK: Bezel and frame lines

    private var bezel: some View {
        ZStack(alignment: .topLeading) {
            // Thin outer blue line, wide blue band, white line framing the printed face; all three
            // are octagons with the watch's cut corners.
            frameLine(x: 23.5, y: 31.5, width: 548.5, height: 472 + e, lineWidth: 3, radius: 24, color: CasioF91W.blue)
            frameLine(x: 36, y: 45.5, width: 520.5, height: 445 + e, lineWidth: 10.5, radius: 22, color: CasioF91W.blue)
            frameLine(x: 50, y: 60, width: 492, height: 417 + e, lineWidth: 2, radius: 18, color: CasioF91W.silver)
        }
    }

    /// A frame line stroked along the given centerline rectangle.
    private func frameLine(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, lineWidth: CGFloat, radius: CGFloat, color: Color
    ) -> some View {
        CutCornerRect(cut: CGSize(width: 40, height: 64), radius: radius)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    // MARK: Printed text and bars

    private var printedFace: some View {
        ZStack(alignment: .topLeading) {
            // CASIO / F-91W
            Text("CASIO")
                .font(CasioF91W.michroma(25.5))
                .tracking(4)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(1.6)
                .place(centerX: 199.5, centerY: 91.75)
            Text("F-91W")
                .font(CasioF91W.archivoBlack(23.6))
                .tracking(5.6)
                .foregroundStyle(CasioF91W.gold)
                .emboldened(0.6)
                .oblique()
                .place(centerX: 398, centerY: 93.5)
            bar(x: 70, y: 125, width: 453)

            // ◀ LIGHT   ALARM  CHRONOGRAPH
            Pointer(left: true).fill(CasioF91W.red).frame(width: 21, height: 7).position(x: 96.75, y: 157.75)
            Text("LIGHT")
                .font(CasioF91W.michroma(12.4))
                .tracking(1)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 157)
            Text("ALARM")
                .font(CasioF91W.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(CasioF91W.gold)
                .emboldened(0.25)
                .place(leading: 227.5, centerY: 154.75, width: 100)
            Text("CHRONOGRAPH")
                .font(CasioF91W.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(CasioF91W.gold)
                .emboldened(0.25)
                .place(trailing: 504.5, centerY: 154.75, width: 200)

        }
        .overlay(alignment: .topLeading) { bottomPrint.offset(y: e) }
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            // ◀ MODE   ALARM  ON · OFF / 24HR ▶
            Pointer(left: true).fill(CasioF91W.red).frame(width: 20, height: 6.5).position(x: 98, y: 404.5)
            Text("MODE")
                .font(CasioF91W.michroma(12.8))
                .tracking(1.1)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 402.75)
            Text("ALARM")
                .font(CasioF91W.michroma(12.8))
                .tracking(0.85)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(0.25)
                .place(leading: 242.75, centerY: 402.75, width: 90)
            Text("ON · OFF / 24HR")
                .font(CasioF91W.michroma(12.8))
                .tracking(0.65)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(0.25)
                .place(trailing: 476.3, centerY: 402.75, width: 170)
            Pointer(left: false).fill(CasioF91W.red).frame(width: 20.5, height: 7).position(x: 497.25, y: 404.25)

            // WATER [WR] RESIST
            bar(x: 70, y: 419, width: 144.5, height: 5.5)
            bar(x: 375, y: 419, width: 148.5, height: 5.5)
            // The WR box: round top corners, cut bottom corners.
            CutCornerRect(cut: CGSize(width: 11, height: 11), bottomCut: CGSize(width: 15, height: 15), radius: 8)
                .stroke(CasioF91W.blue, lineWidth: 3.75)
                .frame(width: 140.6, height: 47)
                .offset(x: 226.6, y: 417.6)
            // The watch's WR is wider than any free extended face; Saira Expanded is stretched.
            Text("WR")
                .font(CasioF91W.sairaExpanded(33.8))
                .foregroundStyle(CasioF91W.red)
                .oblique()
                .scaleEffect(x: 1.6, y: 1)
                .place(centerX: 295.25, centerY: 441.75)
            Text("WATER")
                .font(CasioF91W.michroma(17))
                .tracking(3.35)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(1.3)
                .place(centerX: 158, centerY: 441.5, width: 130)
            Text("RESIST")
                .font(CasioF91W.michroma(17))
                .tracking(4.2)
                .foregroundStyle(CasioF91W.printWhite)
                .emboldened(1.5)
                .place(centerX: 441, centerY: 441.5, width: 130)
            Text("u")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CasioF91W.printWhite.opacity(0.85))
                .place(centerX: 459.5, centerY: 463)
        }
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 6) -> some View {
        Rectangle().fill(CasioF91W.blue).frame(width: width, height: height).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 104, y: 191.5 + e / 4, width: 389.5, height: 184.5 + e / 2)
        return ZStack(alignment: .topLeading) {
            // Silver outline, dark surround, grey-green glass, and the module 593 display.
            LCDWindow(
                frame: CGRect(x: 89, y: 174 + e / 4, width: 414.5, height: 214 + e / 2), outline: CasioF91W.silver,
                glass: glass, backlit: backlit, style: style)
            Module593Display.placed(in: glass, context: context, style: style)
        }
    }
}
