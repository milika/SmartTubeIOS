import SwiftUI

/// The F-105W face on its canvas (see CasioF105W for where the numbers come from).
struct F105WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioF105W.lcd }
    /// The case extension: the line and face grow by it, the panel and LCD window with the window's
    /// edges; the labels below the window move with its bottom, WATER RESIST to the bottom.
    private var stretch: CaseExtension { CaseExtension(amount: CasioF105W.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            faceShapes
            topPrint
            illuminator
            panelNotches.band(.middleSides, of: stretch)
            lcd.band(.display, of: stretch)
            panelLabels.band(.lowerSides, of: stretch)
            InkText(text: "WATER RESIST", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 171, y: 483.5, width: 292.5, height: 24), color: CasioF105W.printWhite, bold: 0.8
                )
                .band(.bottom, of: stretch)
        }
    }

    // MARK: Moulded edge, blue line, face and blue panel (measured on the image)

    private var faceShapes: some View {
        let growth = stretch.caseGrowth
        return ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 66, height: 82), bottomCut: CGSize(width: 54, height: 70), radius: 14)
                .stroke(CasioF105W.bevel, lineWidth: 7.5)
                .frame(width: 514.5, height: 460.5 + growth)
                .offset(x: 61.75, y: 82.75)
            CutCornerRect(cut: CGSize(width: 58, height: 72), bottomCut: CGSize(width: 46, height: 62), radius: 10)
                .fill(CasioF105W.ring)
                .frame(width: 488.5, height: 435 + growth)
                .offset(x: 77, y: 96)
            CutCornerRect(cut: CGSize(width: 53, height: 66), bottomCut: CGSize(width: 41, height: 56), radius: 8)
                .fill(CasioF105W.face)
                .frame(width: 464.5, height: 411 + growth)
                .offset(x: 89, y: 108)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CasioF105W.panel)
                .frame(width: 446.5, height: 329 + 0.75 * stretch.amount)
                .offset(x: 98.5, y: 148)
        }
    }

    /// The blue panel's side strips are broken by a black notch level with the window's middle.
    private var panelNotches: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(CasioF105W.face).frame(width: 22, height: 15.5).offset(x: 98.5, y: 304.5)
            Rectangle().fill(CasioF105W.face).frame(width: 21.5, height: 15.5).offset(x: 523.5, y: 304.5)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            InkText(text: "CASIO", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 152.5, y: 119.5, width: 110.5, height: 21.5), color: CasioF105W.printWhite, bold: 1)
            InkText(text: "ALARM CHRONO", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 280.5, y: 122.5, width: 213.5, height: 19.5), color: CasioF105W.printWhite, bold: 0.6)
        }
    }

    private var illuminator: some View {
        ZStack(alignment: .topLeading) {
            Pointer(left: true).fill(CasioF105W.beige).frame(width: 32.5, height: 15).offset(x: 131, y: 171.5)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 171.5, y: 165, width: 303.5, height: 29), color: CasioF105W.illuminator)
            Pointer(left: false).fill(CasioF105W.beige).frame(width: 34.5, height: 12.5).offset(x: 481, y: 175)
        }
    }

    private var panelLabels: some View {
        ZStack(alignment: .topLeading) {
            dot(x: 128, y: 437)
            RoundedRectangle(cornerRadius: 2).fill(CasioF105W.beige)
                .frame(width: 204.5, height: 18.5).offset(x: 145.5, y: 428.5)
            InkText(text: "EL BACKLIGHT/RESET", font: CaseFont.michroma)
                .placed(in: CGRect(x: 154, y: 431.5, width: 193, height: 13), color: CasioF105W.brown, bold: 0.3)
            dot(x: 127, y: 458.5)
            InkText(text: "MODE", font: CaseFont.michroma)
                .placed(in: CGRect(x: 145.5, y: 451.5, width: 60, height: 14), color: CasioF105W.labelBlue, bold: 0.4)
            InkText(text: "START·STOP/12·24HR", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 250.5, y: 451.5, width: 240.5, height: 16), color: CasioF105W.labelBlue, bold: 0.4)
            dot(x: 509, y: 462.5)
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioF105W.beige).frame(width: 10, height: 10).position(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        LCDPanel(
            display: F105WDisplay.self,
            frame: CGRect(x: 120.5, y: 207.5, width: 403, height: 211.5 + stretch.windowGrowth), frameRadius: 10,
            surround: CasioF105W.frame, outline: .clear, outlineWidth: 0,
            glass: CGRect(x: 128, y: 218, width: 387, height: 193.5 + stretch.windowGrowth), glassRadius: 6,
            context: context, style: style)
    }
}
