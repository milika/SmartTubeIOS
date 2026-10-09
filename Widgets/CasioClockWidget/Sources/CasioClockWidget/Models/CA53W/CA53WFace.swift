import SwiftUI

/// The CA-53W face on its canvas (see CasioCA53W for where the numbers come from): the display
/// section above, the keypad below.
struct CA53WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioCA53W.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panels
            topPrint
            sideLabels
            lcd
            keypad
        }
    }

    // MARK: Panels

    private var panels: some View {
        ZStack(alignment: .topLeading) {
            panel(CGRect(x: 26, y: 28, width: 588, height: 277), fill: CasioCA53W.plate)
            panel(CGRect(x: 26, y: 328, width: 588, height: 378), fill: CasioCA53W.keypadPlate)
        }
    }

    private func panel(_ rect: CGRect, fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(CasioCA53W.panelEdge, lineWidth: 2)
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    // MARK: Display section

    private func ink(_ text: String, _ font: String) -> InkText { InkText(text: text, font: font) }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 89.5, y: 58.5, width: 118, height: 22.5), color: CasioCA53W.printWhite, bold: 0.8)
            ink("WATER RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 242, y: 49, width: 165.5, height: 15), color: CasioCA53W.blue, bold: 0.5)
            ink("ALARM CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 242.5, y: 71, width: 175, height: 15.5), color: CasioCA53W.blue, bold: 0.5)
            ink("WR", CaseFont.archivoBlack)
                .placed(in: CGRect(x: 439.5, y: 52.5, width: 104.5, height: 31), color: CasioCA53W.gold)
        }
    }

    /// "ADJ ◘ ■ MODE/C" beside the display, reading upwards.
    private var sideLabels: some View {
        ZStack(alignment: .topLeading) {
            ink("ADJ", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 569.5, y: 249, width: 13, height: 34), angle: -90, color: CasioCA53W.printWhite,
                    bold: 0.3)
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(CasioCA53W.printWhite, lineWidth: 2.2)
                .frame(width: 12.5, height: 12.5)
                .offset(x: 570, y: 227)
            Rectangle().fill(CasioCA53W.printWhite).frame(width: 12.5, height: 12.5).offset(x: 569.5, y: 204)
            ink("MODE/C", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 569, y: 115, width: 13, height: 78.5), angle: -90, color: CasioCA53W.printWhite,
                    bold: 0.3)
        }
    }

    private var lcd: some View {
        let glass = CGRect(x: 106.5, y: 116, width: 429, height: 173)
        return LCDPanel(
            display: Module3208Display.self, frame: CGRect(x: 93, y: 106, width: 452, height: 190), frameRadius: 10,
            surround: Color(white: 0.07), outline: .clear, outlineWidth: 0, glass: glass, glassRadius: 5,
            context: context, style: style)
    }

    // MARK: Keypad

    /// Key grid: four columns 128.5 apart, four rows 76.7 apart (levelled photo).
    private static func keyFrame(column: Int, row: Int) -> CGRect {
        CGRect(x: 100.5 + 128.5 * CGFloat(column), y: 384.5 + 76.7 * CGFloat(row), width: 64.5, height: 28)
    }

    private var keypad: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4.75).fill(CasioCA53W.bar).frame(width: 499.5, height: 9.5).offset(
                x: 80, y: 354.5)
            ForEach(0..<16, id: \.self) { index in
                let frame = Self.keyFrame(column: index % 4, row: index / 4)
                Capsule().fill(CasioCA53W.key)
                    .overlay(Capsule().strokeBorder(Color(white: 0.22), lineWidth: 1.5))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            digits
            operators
            rules
            functionLabels
        }
    }

    private var digits: some View {
        ZStack(alignment: .topLeading) {
            digit("7", CGRect(x: 62.5, y: 388, width: 23.5, height: 22))
            digit("8", CGRect(x: 190, y: 388.5, width: 23.5, height: 22))
            digit("9", CGRect(x: 318, y: 388, width: 23.5, height: 22))
            digit("4", CGRect(x: 62, y: 464, width: 24, height: 22.5))
            digit("5", CGRect(x: 190, y: 464.5, width: 23.5, height: 22))
            digit("6", CGRect(x: 318, y: 464, width: 23.5, height: 22))
            digit("1", CGRect(x: 67.5, y: 540.5, width: 13, height: 21.5))
            digit("2", CGRect(x: 190, y: 540.5, width: 23.5, height: 22))
            digit("3", CGRect(x: 318, y: 540, width: 23.5, height: 22))
            digit("0", CGRect(x: 61.5, y: 616.5, width: 25, height: 22))
            Rectangle().fill(CasioCA53W.printWhite).frame(width: 10, height: 10.5).offset(x: 196.5, y: 614)
            ink("PM", CaseFont.michroma)
                .placed(in: CGRect(x: 186.5, y: 630.5, width: 29, height: 14), color: CasioCA53W.printWhite, bold: 0.3)
        }
    }

    private func digit(_ text: String, _ box: CGRect) -> some View {
        ink(text, CaseFont.michroma).placed(in: box, color: CasioCA53W.printWhite, bold: 1.1)
    }

    /// ÷ × − + and = in thin red strokes.
    private var operators: some View {
        let red = CasioCA53W.red
        return ZStack(alignment: .topLeading) {
            // ÷
            Rectangle().fill(red).frame(width: 13, height: 3).offset(x: 443, y: 397)
            Circle().fill(red).frame(width: 4, height: 4).offset(x: 447.5, y: 388.5)
            Circle().fill(red).frame(width: 4, height: 4).offset(x: 447.5, y: 404.5)
            // ×
            ZStack {
                Rectangle().fill(red).frame(width: 18, height: 3).rotationEffect(.degrees(45))
                Rectangle().fill(red).frame(width: 18, height: 3).rotationEffect(.degrees(-45))
            }
            .frame(width: 14.5, height: 16)
            .offset(x: 444.5, y: 466.5)
            // −
            Rectangle().fill(red).frame(width: 18.5, height: 4).offset(x: 443.5, y: 548.5)
            // +
            Rectangle().fill(red).frame(width: 16, height: 3.5).offset(x: 443.5, y: 624.25)
            Rectangle().fill(red).frame(width: 3.5, height: 19).offset(x: 449.75, y: 616.5)
            // =
            Rectangle().fill(red).frame(width: 11, height: 3).offset(x: 316.5, y: 622)
            Rectangle().fill(red).frame(width: 11, height: 3).offset(x: 316.5, y: 631)
        }
    }

    /// The white rules between the key rows.
    private var rules: some View {
        ZStack(alignment: .topLeading) {
            rule(47.5, 436, 74)
            rule(280.5, 435.5, 83.5)
            rule(533.5, 435, 52)
            rule(47.5, 511.25, 332, height: 4)
            rule(533.5, 510.75, 52)
            rule(47, 587.75, 74.5)
            rule(265.5, 587.75, 106.5)
            rule(534, 587.25, 51.5)
            rule(60, 664, 513, height: 3.5)
        }
    }

    private func rule(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, height: CGFloat = 3) -> some View {
        Rectangle().fill(CasioCA53W.lineWhite).frame(width: width, height: height).offset(x: x, y: y)
    }

    /// ▼ ALM ON·OFF, DATE/ST-Hour ▲, SIG ON·OFF ▲, ▼ LAP·RESET ◀, START·STOP ▼.
    private var functionLabels: some View {
        let tan = CasioCA53W.tan
        return ZStack(alignment: .topLeading) {
            triangle(.down, CGRect(x: 128.5, y: 431, width: 13, height: 10))
            ink("ALM ON·OFF", CaseFont.michroma)
                .placed(in: CGRect(x: 146, y: 431.5, width: 124.5, height: 11.5), color: tan, bold: 0.3)
            ink("DATE/ST-Hour", CaseFont.michroma)
                .placed(in: CGRect(x: 373.5, y: 430.5, width: 128, height: 12.5), color: tan, bold: 0.3)
            triangle(.up, CGRect(x: 513, y: 432, width: 11, height: 10))
            ink("SIG ON·OFF", CaseFont.michroma)
                .placed(in: CGRect(x: 389.5, y: 506.5, width: 112, height: 12), color: tan, bold: 0.3)
            triangle(.up, CGRect(x: 512.5, y: 505.5, width: 11.5, height: 13))
            triangle(.down, CGRect(x: 127.5, y: 583, width: 14.5, height: 11))
            ink("LAP·RESET", CaseFont.michroma)
                .placed(in: CGRect(x: 146, y: 583, width: 98, height: 12), color: tan, bold: 0.3)
            triangle(.left, CGRect(x: 247, y: 585, width: 9.5, height: 8))
            ink("START·STOP", CaseFont.michroma)
                .placed(in: CGRect(x: 383, y: 582.5, width: 126, height: 12.5), color: tan, bold: 0.3)
            triangle(.down, CGRect(x: 513, y: 582.5, width: 13.5, height: 10.5))
        }
    }

    private enum Direction { case up, down, left }

    private func triangle(_ direction: Direction, _ box: CGRect) -> some View {
        Triangle(direction: direction).fill(CasioCA53W.tan).frame(width: box.width, height: box.height)
            .offset(x: box.minX, y: box.minY)
    }

    private struct Triangle: Shape {
        let direction: Direction

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch direction {
            case .up:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .down:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            case .left:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            path.closeSubpath()
            return path
        }
    }
}
