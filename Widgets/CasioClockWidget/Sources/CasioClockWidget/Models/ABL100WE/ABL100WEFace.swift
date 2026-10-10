import SwiftUI

/// The ABL-100WE face on its canvas (see CasioABL100WE for where the numbers come from).
struct ABL100WEFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioABL100WE.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plateAndLines
            topPrint
            sideLabels
            lcd
            bottomPrint
        }
    }

    // MARK: Plate and lines (octagons measured on the image)

    private var plateAndLines: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 62, height: 100), bottomCut: CGSize(width: 72, height: 96), radius: 30)
                .fill(CasioABL100WE.plate)
                .frame(width: 490.5, height: 442).offset(x: 62.5, y: 122)
            CutCornerRect(cut: CGSize(width: 55, height: 92), bottomCut: CGSize(width: 66, height: 89), radius: 26)
                .stroke(CasioABL100WE.blue, lineWidth: 5.5)
                .frame(width: 459.5, height: 417.5).offset(x: 79, y: 134.5)
            CutCornerRect(cut: CGSize(width: 48, height: 82), bottomCut: CGSize(width: 58, height: 79), radius: 22)
                .stroke(CasioABL100WE.line, lineWidth: 2.5)
                .frame(width: 439, height: 396.5).offset(x: 87.5, y: 144.5)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private func ink(
        _ text: String, _ box: CGRect, _ color: Color, bold: CGFloat = 0.6, barBold: CGFloat? = nil
    )
        -> some View
    {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: color, bold: bold, barBold: barBold)
    }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink(
                "CASIO", CGRect(x: 159.5, y: 168, width: 103.5, height: 19), CasioABL100WE.printWhite, bold: 1.2,
                barBold: 0.75)
            ink("STEP", CGRect(x: 292.5, y: 170, width: 51.5, height: 14.5), CasioABL100WE.gold, bold: 1, barBold: 0.6)
            ink(
                "TRACKER", CGRect(x: 355.5, y: 170, width: 100.5, height: 14.5), CasioABL100WE.gold, bold: 1,
                barBold: 0.6)
            Pointer(left: true).fill(CasioABL100WE.blueprint).frame(width: 19.5, height: 17).offset(x: 195, y: 202.5)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 217.5, y: 201.5, width: 188.5, height: 19), color: CasioABL100WE.blueprint)
            Pointer(left: false).fill(CasioABL100WE.blueprint).frame(width: 21, height: 16).offset(x: 408.5, y: 202.5)
        }
    }

    /// ADJUST and MODE read downwards on the left, LIGHT and SEARCH upwards on the right, red dots by
    /// the buttons.
    private var sideLabels: some View {
        let white = CasioABL100WE.printWhite
        return ZStack(alignment: .topLeading) {
            dot(CGRect(x: 112, y: 239.5, width: 14.5, height: 14))
            InkText(text: "ADJUST", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 108, y: 262.5, width: 16.5, height: 80.5), angle: 90, color: white, bold: 0.8)
            InkText(text: "MODE", font: CaseFont.michroma)
                .placed(vertical: CGRect(x: 110, y: 363, width: 15, height: 58.5), angle: 90, color: white, bold: 0.8)
            dot(CGRect(x: 112, y: 433, width: 13.5, height: 14.5))
            dot(CGRect(x: 489.5, y: 238.5, width: 14, height: 15))
            InkText(text: "LIGHT", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 490, y: 262.5, width: 14.5, height: 56.5), angle: -90, color: white, bold: 0.8)
            InkText(text: "SEARCH", font: CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 488.5, y: 342.5, width: 16, height: 82), angle: -90, color: white, bold: 0.8)
            dot(CGRect(x: 488.5, y: 434.5, width: 15, height: 14.5))
        }
    }

    private func dot(_ box: CGRect) -> some View {
        Circle().fill(CasioABL100WE.red).frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
    }

    private var bottomPrint: some View {
        let red = CasioABL100WE.red
        return ZStack(alignment: .topLeading) {
            ink("WATER", CGRect(x: 179.5, y: 470, width: 76, height: 12), red, bold: 1, barBold: 0.6)
            CutCornerRect(cut: CGSize(width: 6, height: 6), radius: 3)
                .stroke(red, lineWidth: 2.5)
                .frame(width: 75.5, height: 25).offset(x: 268.75, y: 463.75)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.22)
                .placed(in: CGRect(x: 281.5, y: 469.5, width: 50.5, height: 14.5), color: red)
            ink("RESIST", CGRect(x: 356.5, y: 470, width: 79.5, height: 13.5), red, bold: 1, barBold: 0.6)
            Rectangle().fill(CasioABL100WE.rule).frame(width: 341, height: 3).offset(x: 139, y: 498.5)
            InkText(text: "Bluetooth", font: CaseFont.saira)
                .placed(in: CGRect(x: 267.5, y: 510, width: 73.5, height: 17.5), color: CasioABL100WE.gold, bold: 0.6)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        LCDPanel(
            display: ABL100WEDisplay.self, frame: CGRect(x: 153, y: 241, width: 317.5, height: 214), frameRadius: 12,
            surround: CasioABL100WE.plate, outline: .clear, outlineWidth: 0,
            glass: CGRect(x: 156, y: 244, width: 311.5, height: 208), glassRadius: 10, context: context, style: style)
    }
}
