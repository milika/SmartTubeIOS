import SwiftUI

/// The A178W face on its canvas (see CasioA178W for where the numbers come from).
struct A178WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioA178W.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ringAndPlate
            topPrint
            sideLabels
            lcd
            bottomPrint
        }
    }

    // MARK: Ring and face (octagons, measured on the image)

    private var ringAndPlate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(
                cut: CGSize(width: 51.5, height: 51.5), bottomCut: CGSize(width: 43.5, height: 47.5), radius: 14
            )
            .fill(CasioA178W.ring)
            .frame(width: 440.5, height: 428.5)
            .offset(x: 73, y: 95)
            CutCornerRect(cut: CGSize(width: 48, height: 48), bottomCut: CGSize(width: 40, height: 44), radius: 12)
                .fill(CasioA178W.plate)
                .frame(width: 427, height: 417.5)
                .offset(x: 80, y: 101)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private var topPrint: some View {
        let white = CasioA178W.printWhite
        return ZStack(alignment: .topLeading) {
            InkText(text: "CASIO", font: CaseFont.michroma)
                .placed(in: CGRect(x: 142, y: 115.5, width: 108, height: 22), color: white, bold: 0.9)
            Pointer(left: true).fill(white).frame(width: 17.5, height: 10).offset(x: 272, y: 108)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 292, y: 106, width: 143.5, height: 14.5), color: white)
            Pointer(left: false).fill(white).frame(width: 18.5, height: 9.5).offset(x: 437, y: 109.5)
            InkText(text: "ALARM CHRONO", font: CaseFont.michroma)
                .placed(in: CGRect(x: 272, y: 125.5, width: 183, height: 15), color: white, bold: 0.6)
        }
    }

    /// ADJUST and MODE read downwards on the left, LIGHT and START/STOP upwards on the right, each
    /// with a small bar by its button.
    private var sideLabels: some View {
        let white = CasioA178W.printWhite
        return ZStack(alignment: .topLeading) {
            bar(x: 93.5, y: 181, height: 20)
            InkText(text: "ADJUST", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 88.5, y: 206.5, width: 16, height: 73.5), angle: 90, color: white, bold: 0.4)
            InkText(text: "MODE", font: CaseFont.michroma)
                .placed(vertical: CGRect(x: 87, y: 361, width: 15, height: 60), angle: 90, color: white, bold: 0.4)
            bar(x: 90.5, y: 429.5, height: 20)
            bar(x: 489.5, y: 178, height: 20)
            InkText(text: "LIGHT", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 487, y: 200.5, width: 15.5, height: 60), angle: -90, color: white, bold: 0.4)
            InkText(text: "START/STOP", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 486.5, y: 302, width: 16, height: 117.5), angle: -90, color: white, bold: 0.4)
            bar(x: 487, y: 428, height: 20)
        }
    }

    private func bar(x: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(CasioA178W.printWhite).frame(width: 9, height: height).offset(x: x, y: y)
    }

    private var bottomPrint: some View {
        let white = CasioA178W.printWhite
        return ZStack(alignment: .topLeading) {
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.2)
                .placed(in: CGRect(x: 134.5, y: 486.5, width: 101.5, height: 25.5), color: CasioA178W.blue)
            InkText(text: "DUAL TIME", font: CaseFont.michroma, tracking: 0.2)
                .placed(in: CGRect(x: 259.5, y: 485, width: 190, height: 17.5), color: white, bold: 0.5)
            InkText(text: "10YEAR BATTERY", font: CaseFont.michroma)
                .placed(in: CGRect(x: 258, y: 503, width: 191.5, height: 16.5), color: white, bold: 0.5)
            Rectangle().fill(white).frame(width: 6.5, height: 2).offset(x: 243, y: 520.5)
            InkText(text: "u", font: CaseFont.saira)
                .placed(in: CGRect(x: 253, y: 519, width: 5, height: 4.5), color: white)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        LCDPanel(
            display: A178WDisplay.self, frame: CGRect(x: 119.5, y: 146.5, width: 351.5, height: 333.5),
            frameRadius: 14, surround: CasioA178W.plate, outline: CasioA178W.outline, outlineWidth: 4.5,
            glass: CGRect(x: 129.5, y: 156, width: 329.5, height: 312), glassRadius: 8, context: context, style: style)
    }
}
