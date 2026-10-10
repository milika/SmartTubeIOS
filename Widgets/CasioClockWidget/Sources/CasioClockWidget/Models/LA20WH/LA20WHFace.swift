import SwiftUI

/// The LA-20WH face on its canvas (see CasioLA20WH for where the numbers come from).
struct LA20WHFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioLA20WH.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            caseShape
            faceShapes
            print
            lcd
        }
    }

    // MARK: Case

    private var caseShape: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.buttons.enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 4).fill(CasioLA20WH.chrome)
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            }
            CutCornerRect(cut: CGSize(width: 70, height: 72), bottomCut: CGSize(width: 64, height: 66), radius: 26)
                .fill(CasioLA20WH.resin)
                .frame(width: 489, height: 402).offset(x: 38, y: 58)
            CutCornerRect(cut: CGSize(width: 70, height: 72), bottomCut: CGSize(width: 64, height: 66), radius: 26)
                .stroke(CasioLA20WH.resinEdge, lineWidth: 2)
                .frame(width: 489, height: 402).offset(x: 38, y: 58)
        }
    }

    private static let buttons = [
        CGRect(x: 26, y: 125, width: 14, height: 34), CGRect(x: 26, y: 340, width: 14, height: 34),
        CGRect(x: 520, y: 340, width: 14, height: 34),
    ]

    // MARK: White line, slate line, face

    private var faceShapes: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 58, height: 58), bottomCut: CGSize(width: 56, height: 54), radius: 20)
                .stroke(CasioLA20WH.printWhite, lineWidth: 2.75)
                .frame(width: 356, height: 322.25).offset(x: 93.75, y: 90.75)
            CutCornerRect(cut: CGSize(width: 52, height: 52), bottomCut: CGSize(width: 50, height: 48), radius: 16)
                .fill(CasioLA20WH.slateLine)
                .frame(width: 348, height: 315).offset(x: 98.5, y: 95.5)
            CutCornerRect(cut: CGSize(width: 48, height: 48), bottomCut: CGSize(width: 46, height: 44), radius: 13)
                .fill(CasioLA20WH.face)
                .frame(width: 334, height: 301).offset(x: 105.5, y: 102.5)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private func ink(_ text: String, _ box: CGRect, _ color: Color, bold: CGFloat = 0.5) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: color, bold: bold)
    }

    private var print: some View {
        let white = CasioLA20WH.printWhite, slate = CasioLA20WH.slate
        return ZStack(alignment: .topLeading) {
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 178, y: 64, width: 194.5, height: 14), color: white)
            ink("WATER RESIST", CGRect(x: 183.5, y: 424, width: 177.5, height: 17), white, bold: 1.1)
            ink("CASIO", CGRect(x: 223.5, y: 116, width: 88.5, height: 16.5), white, bold: 1)
            Pointer(left: true).fill(slate).frame(width: 10.5, height: 10.5).offset(x: 133, y: 142)
            ink("START", CGRect(x: 150, y: 142, width: 51, height: 11), slate)
            ink("/", CGRect(x: 203, y: 143, width: 5, height: 8), slate)
            ink("STOP", CGRect(x: 212, y: 142.5, width: 41.5, height: 11), slate)
            ink("ALARM", CGRect(x: 275, y: 143.5, width: 56.5, height: 10), slate)
            ink("CHRONO", CGRect(x: 339, y: 143.5, width: 71.5, height: 10.5), slate)
            Pointer(left: true).fill(slate).frame(width: 11, height: 11).offset(x: 129, y: 348.5)
            ink("MODE", CGRect(x: 146, y: 349, width: 47, height: 11), slate)
            ink("LIGHT", CGRect(x: 345, y: 349.5, width: 47.5, height: 11), slate)
            Pointer(left: false).fill(slate).frame(width: 11.5, height: 11).offset(x: 398.5, y: 350)
            RoundedRectangle(cornerRadius: 6).strokeBorder(slate, lineWidth: 2.5)
                .frame(width: 98.5, height: 38.5).offset(x: 219.5, y: 349.5)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.25)
                .placed(in: CGRect(x: 239, y: 359, width: 60.5, height: 19.5), color: slate)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        LCDPanel(
            display: LA20WHDisplay.self, frame: CGRect(x: 149.5, y: 162.5, width: 246.5, height: 178.5),
            frameRadius: 13, surround: CasioLA20WH.face, outline: CasioLA20WH.printWhite, outlineWidth: 3.75,
            glass: CGRect(x: 154, y: 167, width: 237.5, height: 169), glassRadius: 9, context: context, style: style)
    }
}
