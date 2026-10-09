import SwiftUI

/// The W-86 face on its canvas (see CasioW86 for where the numbers come from).
struct W86Face: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioW86.lcd }
    /// The case extension: ring and face grow by it, the LCD window by half; side labels and the
    /// print below move down.
    private var stretch: CaseExtension { CaseExtension(amount: CasioW86.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ringAndPlate
            topPrint
            sideLabels
            lcd.band(.display, of: stretch)
            bottomPrint.band(.bottom, of: stretch)
        }
    }

    // MARK: Ring and face

    private var ringAndPlate: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 72, height: 80), bottomCut: CGSize(width: 66, height: 62), radius: 26)
                .fill(CasioW86.ring)
                .frame(width: 701.5, height: 579.5 + stretch.caseGrowth)
                .offset(x: 7.5, y: 26.5)
            CutCornerRect(cut: CGSize(width: 64, height: 72), bottomCut: CGSize(width: 58, height: 54), radius: 22)
                .fill(CasioW86.plate)
                .frame(width: 671, height: 556 + stretch.caseGrowth)
                .offset(x: 24, y: 40)
        }
    }

    // MARK: Print

    private func ink(_ text: String, _ font: String, slant: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, slant: slant)
    }

    private var topPrint: some View {
        let white = CasioW86.printWhite
        return ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 163, y: 63, width: 171, height: 30), color: white, bold: 1)
            ink("ALARM CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 351, y: 65.5, width: 234, height: 21.5), color: white, bold: 0.7)
            Slanted(points: [(58, 159), (151, 89), (151, 108), (128, 159)]).fill(CasioW86.teal)
            Slanted(points: [(146, 108.5), (591.5, 108.5), (581, 158.5), (131, 158.5)]).fill(CasioW86.teal)
            Slanted(points: [(594, 108), (618.5, 108), (608, 155.5), (583.5, 155.5)]).fill(CasioW86.teal)
            Slanted(points: [(621, 108), (645.5, 108), (635.5, 155), (611, 155)]).fill(CasioW86.teal)
            ink("ELECTRO LUMINESCENCE", CaseFont.michroma, slant: 0.2)
                .placed(in: CGRect(x: 149.5, y: 121, width: 417, height: 24.5), color: CasioW86.plate, bold: 0.6)
        }
    }

    /// LIGHT and MODE read downwards on the left, START·STOP upwards on the right; red dots.
    private var sideLabels: some View {
        let white = CasioW86.printWhite
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                dot(x: 56, y: 183)
                ink("LIGHT", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 41, y: 200.5, width: 20, height: 68.5), angle: 90, color: white, bold: 0.6)
            }
            .band(.upperSides, of: stretch)
            ZStack(alignment: .topLeading) {
                ink("MODE", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 34, y: 358.5, width: 20.5, height: 70.5), angle: 90, color: white, bold: 0.6
                    )
                dot(x: 44, y: 447.75)
                ink("START·STOP", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 661, y: 269.5, width: 18.5, height: 156), angle: -90, color: white,
                        bold: 0.6)
                dot(x: 673, y: 445)
            }
            .band(.lowerSides, of: stretch)
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioW86.red).frame(width: 17, height: 17).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CasioW86.teal)
                .frame(width: 584, height: 58)
                .offset(x: 65, y: 471)
            Pointer(left: true).fill(CasioW86.plate).frame(width: 48, height: 20).offset(x: 105, y: 490.5)
            ink("ILLUMINATOR", CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 161, y: 485, width: 390.5, height: 29), color: CasioW86.plate)
            Pointer(left: false).fill(CasioW86.plate).frame(width: 50.5, height: 19).offset(x: 559, y: 489.5)
            ink("WATER 50M RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 123, y: 541.5, width: 461.5, height: 29), color: CasioW86.printWhite, bold: 1.2)
            InkText(text: "u", font: CaseFont.saira)
                .placed(in: CGRect(x: 348, y: 580.5, width: 8, height: 8.5), color: CasioW86.printWhite.opacity(0.85))
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 86, y: 201.5, width: 536.5, height: 237.5 + stretch.windowGrowth)
        return LCDPanel(
            display: W86Display.self, frame: CGRect(x: 68, y: 170, width: 581, height: 287 + stretch.windowGrowth),
            frameRadius: 32, surround: CasioW86.frame, outline: .clear, outlineWidth: 0, glass: glass, glassRadius: 18,
            context: context, style: style)
    }
}

/// A filled polygon from canvas points (the teal band and stripes), drawn in the face's coordinates.
private struct Slanted: Shape {
    let points: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }
}
