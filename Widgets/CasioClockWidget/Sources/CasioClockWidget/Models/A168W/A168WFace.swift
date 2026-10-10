import SwiftUI

/// The A168W face on its canvas (see CasioA168W for where the numbers come from).
struct A168WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioA168W.lcd }
    /// The case extension: lines grow by it, the LCD window by half; side labels and the print below
    /// move down to share the space.
    private var stretch: CaseExtension { CaseExtension(amount: CasioA168W.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            plateAndLines
            topPrint
            sideLabels
            lcd.band(.display, of: stretch)
            bottomPrint.band(.bottom, of: stretch)
        }
    }

    // MARK: Plate and lines

    private var plateAndLines: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 64, height: 74), bottomCut: CGSize(width: 66, height: 52), radius: 28)
                .fill(CasioA168W.plate)
                .frame(width: 430, height: 380 + stretch.caseGrowth)
                .offset(x: 60, y: 49)
            CutCornerRect(cut: CGSize(width: 58, height: 68), bottomCut: CGSize(width: 60, height: 46), radius: 24)
                .stroke(CasioA168W.blue, lineWidth: 5.5)
                .frame(width: 398.5, height: 345.75 + stretch.caseGrowth)
                .offset(x: 77.25, y: 66.75)
            CutCornerRect(cut: CGSize(width: 50, height: 60), bottomCut: CGSize(width: 52, height: 38), radius: 20)
                .stroke(CasioA168W.line, lineWidth: 2.5)
                .frame(width: 377.75, height: 326 + stretch.caseGrowth)
                .offset(x: 88, y: 76)
        }
    }

    // MARK: Print

    private func ink(_ text: String, _ font: String, slant: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, slant: slant)
    }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(
                    in: CGRect(x: 149.5, y: 96.5, width: 97.5, height: 17.5), color: CasioA168W.printWhite, bold: 0.95,
                    barBold: 0.6)
            ink("ALARM CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 270, y: 99.5, width: 142.5, height: 11), color: CasioA168W.gold, bold: 0.75)
            Banner().fill(CasioA168W.banner).frame(width: 288, height: 28).offset(x: 128.5, y: 126.5)
            // ELECTRO LUMINESCENCE: tall E and L, small caps, italic.
            ink("E", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 158.5, y: 131.5, width: 15.5, height: 17), color: CasioA168W.printWhite)
            ink("LECTRO", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 175, y: 136.5, width: 67, height: 11.5), color: CasioA168W.printWhite)
            ink("L", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 245.5, y: 130.5, width: 13, height: 18), color: CasioA168W.printWhite)
            ink("UMINESCENCE", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 261, y: 136.5, width: 133.5, height: 11.5), color: CasioA168W.printWhite)
        }
    }

    /// LIGHT and MODE read downwards on the left, START/STOP upwards on the right, red dots by the
    /// buttons.
    private var sideLabels: some View {
        ZStack(alignment: .topLeading) {
            dot(x: 113.25, y: 157.25)
            ink("LIGHT", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 105.5, y: 172, width: 12, height: 53.5), angle: 90,
                    color: CasioA168W.printWhite, bold: 0.55
                )
                .band(.upperSides, of: stretch)
            ink("MODE", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 104.5, y: 259.5, width: 13.5, height: 54.5), angle: 90,
                    color: CasioA168W.printWhite, bold: 0.55
                )
                .band(.lowerSides, of: stretch)
            dot(x: 113, y: 327).band(.bottom, of: stretch)
            ink("START/STOP", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 435, y: 188.5, width: 16.5, height: 126), angle: -90,
                    color: CasioA168W.printWhite, bold: 0.55
                )
                .band(.middleSides, of: stretch)
            dot(x: 439, y: 327.5).band(.bottom, of: stretch)
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioA168W.red).frame(width: 12.5, height: 12.5).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            Arrow(left: true).fill(CasioA168W.red).frame(width: 16.5, height: 13.5).offset(x: 165.5, y: 327)
            ink("ILLUMINATOR", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 187, y: 326, width: 176.5, height: 15.5), color: CasioA168W.red)
            Arrow(left: false).fill(CasioA168W.red).frame(width: 18.5, height: 13).offset(x: 367.5, y: 327.5)
            Rectangle().fill(CasioA168W.line).frame(width: 303.5, height: 3).offset(x: 124.5, y: 354.5)
            ink("WATER", CaseFont.michroma)
                .placed(in: CGRect(x: 153.5, y: 371, width: 73, height: 11.5), color: CasioA168W.gold, bold: 0.75)
            CutCornerRect(cut: CGSize(width: 7, height: 7), radius: 3)
                .stroke(CasioA168W.gold, lineWidth: 2)
                .frame(width: 75.5, height: 26)
                .offset(x: 239.5, y: 364.5)
            ink("WR", CaseFont.sairaExpanded, slant: 0.2)
                .placed(in: CGRect(x: 253, y: 371, width: 49, height: 14), color: CasioA168W.gold)
            ink("RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 327.5, y: 371.5, width: 74, height: 10.5), color: CasioA168W.gold, bold: 0.75)
        }
    }

    // MARK: LCD (module 3298)

    private var lcd: some View {
        let glass = CGRect(x: 136, y: 171, width: 280.5, height: 138 + stretch.windowGrowth)
        return LCDPanel(
            display: Module3298Display.self,
            frame: CGRect(x: 131, y: 166, width: 290.5, height: 148 + stretch.windowGrowth),
            frameRadius: 12, surround: Color(white: 0.08), outline: .clear, outlineWidth: 0, glass: glass,
            glassRadius: 9, context: context, style: style)
    }
}

/// The ElectroLuminescence banner: a band with an arrow point on the left.
private struct Banner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let point = rect.height * 0.75
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + point, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The small arrows either side of ILLUMINATOR.
private struct Arrow: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if left {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
