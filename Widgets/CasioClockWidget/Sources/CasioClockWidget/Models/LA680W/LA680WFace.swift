import SwiftUI

/// The LA680W face on its canvas (see CasioLA680W for where the numbers come from).
struct LA680WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioLA680W.lcd }
    /// The case extension: rim, line and face grow by it, the LCD window by half; side labels and
    /// the print below move down.
    private var stretch: CaseExtension { CaseExtension(amount: CasioLA680W.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plate
            InkText(text: "CASIO", font: CaseFont.michroma)
                .placed(
                    in: CGRect(x: 252.5, y: 174.5, width: 118, height: 21.5), color: CasioLA680W.printWhite, bold: 0.8)
            upperSides.band(.upperSides, of: stretch)
            lowerSides.band(.lowerSides, of: stretch)
            lcd.band(.display, of: stretch)
            bottomPrint.band(.bottom, of: stretch)
        }
    }

    // MARK: Rim, line and face (octagons, measured on the image)

    private var plate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 62, height: 108), bottomCut: CGSize(width: 58, height: 104), radius: 14)
                .fill(CasioLA680W.rim)
                .frame(width: 506.5, height: 453.5 + stretch.caseGrowth)
                .offset(x: 58, y: 127.5)
            CutCornerRect(cut: CGSize(width: 56, height: 98), bottomCut: CGSize(width: 52, height: 95), radius: 10)
                .fill(CasioLA680W.line)
                .frame(width: 482.5, height: 430 + stretch.caseGrowth)
                .offset(x: 70, y: 138.5)
            CutCornerRect(cut: CGSize(width: 52, height: 94), bottomCut: CGSize(width: 48, height: 92), radius: 8)
                .fill(CasioLA680W.plate)
                .frame(width: 469, height: 416.5 + stretch.caseGrowth)
                .offset(x: 77, y: 145.5)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private var upperSides: some View {
        ZStack(alignment: .topLeading) {
            dot(x: 110, y: 241.75, size: 10.5, color: CasioLA680W.printWhite)
            InkText(text: "START", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 102.5, y: 255, width: 14, height: 59.5), angle: -90,
                    color: CasioLA680W.printWhite, bold: 0.4)
        }
    }

    private var lowerSides: some View {
        ZStack(alignment: .topLeading) {
            InkText(text: "MODE", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 101, y: 397, width: 14, height: 55), angle: 90, color: CasioLA680W.printWhite,
                    bold: 0.4)
            dot(x: 108.25, y: 463.75, size: 10.5, color: CasioLA680W.printWhite)
            InkText(text: "LIGHT", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 505, y: 393.5, width: 14.5, height: 60), angle: -90,
                    color: CasioLA680W.printGrey,
                    bold: 0.4)
            dot(x: 511.5, y: 465.5, size: 9, color: CasioLA680W.printGrey)
        }
    }

    private func dot(x: CGFloat, y: CGFloat, size: CGFloat, color: Color) -> some View {
        Circle().fill(color).frame(width: size, height: size).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        let white = CasioLA680W.printWhite
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(white).frame(width: 26.5, height: 3).offset(x: 143, y: 507.5)
            InkText(text: "WATER", font: CaseFont.michroma)
                .placed(in: CGRect(x: 179.5, y: 501.5, width: 74.5, height: 16), color: white, bold: 0.6)
            CutCornerRect(cut: CGSize(width: 9, height: 9), radius: 4)
                .stroke(white, lineWidth: 2)
                .frame(width: 88, height: 26.5)
                .offset(x: 264.5, y: 496.5)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.2)
                .placed(in: CGRect(x: 282, y: 502.5, width: 55, height: 15), color: white)
            InkText(text: "RESIST", font: CaseFont.michroma)
                .placed(in: CGRect(x: 365, y: 502.5, width: 74, height: 16), color: white, bold: 0.6)
            Rectangle().fill(white).frame(width: 24.5, height: 3).offset(x: 450, y: 509.5)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 205, y: 534.5, width: 208, height: 14.5), color: CasioLA680W.printGrey)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 159.5, y: 248, width: 300.5, height: 211.5 + stretch.windowGrowth)
        return LCDPanel(
            display: LA680WDisplay.self,
            frame: CGRect(x: 130.5, y: 223.5, width: 360, height: 260.5 + stretch.windowGrowth), frameRadius: 18,
            surround: CasioLA680W.plate, outline: CasioLA680W.windowOutline, outlineWidth: 4.5, glass: glass,
            glassRadius: 8, context: context, style: style)
    }
}
