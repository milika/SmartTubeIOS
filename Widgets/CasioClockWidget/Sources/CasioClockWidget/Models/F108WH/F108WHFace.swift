import SwiftUI

/// The F-108WH face on its canvas (see CasioF108WH for where the numbers come from).
struct F108WHFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioF108WH.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            caseShape
            faceShapes
            print
            lcd
            badge
        }
    }

    // MARK: Case

    private var caseShape: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.buttons.enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 5).fill(CasioF108WH.chrome)
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            }
            ForEach(Array(Self.guards.enumerated()), id: \.offset) { _, box in
                RoundedRectangle(cornerRadius: 6).fill(CasioF108WH.guardBlock)
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            }
            CutCornerRect(cut: CGSize(width: 92, height: 66), bottomCut: CGSize(width: 66, height: 72), radius: 24)
                .fill(CasioF108WH.resin)
                .frame(width: 628, height: 516).offset(x: 44, y: 116)
            ForEach(Array(Self.screws.enumerated()), id: \.offset) { _, center in
                Circle().fill(CasioF108WH.screw).frame(width: 24, height: 24)
                    .offset(x: center.x - 12, y: center.y - 12)
            }
        }
    }

    private static let buttons = [
        CGRect(x: 32, y: 222, width: 20, height: 40), CGRect(x: 30, y: 505, width: 20, height: 43),
        CGRect(x: 655, y: 508, width: 23, height: 48),
    ]

    /// The raised blocks on the case's sides.
    private static let guards = [
        CGRect(x: 20.5, y: 320, width: 40, height: 130), CGRect(x: 640, y: 310, width: 59, height: 145),
    ]

    private static let screws = [
        CGPoint(x: 137.5, y: 196.5), CGPoint(x: 562.5, y: 197.5), CGPoint(x: 135, y: 572.5),
        CGPoint(x: 557.5, y: 577.5),
    ]

    // MARK: Gold line, face, blue panel

    private var faceShapes: some View {
        ZStack(alignment: .topLeading) {
            // The gold line is bevelled: lit on its right and lower faces, shaded on its left and top.
            CutCornerRect(cut: CGSize(width: 77, height: 108), bottomCut: CGSize(width: 76, height: 92), radius: 14)
                .fill(CasioF108WH.goldShade)
                .frame(width: 451, height: 408).offset(x: 118.5, y: 183)
            CutCornerRect(cut: CGSize(width: 72, height: 104), bottomCut: CGSize(width: 74, height: 90), radius: 13)
                .fill(CasioF108WH.gold)
                .frame(width: 443, height: 404).offset(x: 126.5, y: 186)
            CutCornerRect(cut: CGSize(width: 70, height: 98), bottomCut: CGSize(width: 69, height: 84), radius: 10)
                .fill(CasioF108WH.face)
                .frame(width: 415, height: 374).offset(x: 136.5, y: 200)
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(CasioF108WH.panel)
                .frame(width: 376.5, height: 286).offset(x: 157.5, y: 244)
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private func ink(_ text: String, _ box: CGRect, _ color: Color, bold: CGFloat = 0.5) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: color, bold: bold)
    }

    private var print: some View {
        ZStack(alignment: .topLeading) {
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 215.5, y: 143.5, width: 261, height: 19.5), color: CasioF108WH.goldPrint)
            ink("WATER RESIST", CGRect(x: 219.5, y: 610, width: 247, height: 24), CasioF108WH.goldPrint, bold: 1.2)
            ink("CASIO", CGRect(x: 290, y: 213, width: 112, height: 21), CasioF108WH.printWhite, bold: 1)
            Pointer(left: true).fill(CasioF108WH.printGrey).frame(width: 16, height: 7.5).offset(x: 193.5, y: 256.5)
            ink("START", CGRect(x: 218.5, y: 255.5, width: 47, height: 9), CasioF108WH.printWhite)
            ink("/", CGRect(x: 267, y: 255, width: 5, height: 10), CasioF108WH.printWhite)
            ink("STOP", CGRect(x: 275.5, y: 255, width: 39.5, height: 10.5), CasioF108WH.printWhite)
            ink("ALARM", CGRect(x: 366, y: 256, width: 52.5, height: 9), CasioF108WH.printWhite)
            ink("CHRONO", CGRect(x: 426, y: 256, width: 67, height: 10.5), CasioF108WH.printWhite)
            Pointer(left: true).fill(CasioF108WH.printGrey).frame(width: 16.5, height: 6).offset(x: 190.5, y: 509.5)
            ink("MODE", CGRect(x: 216.5, y: 509, width: 41.5, height: 10), CasioF108WH.printWhite)
            ink("LIGHT", CGRect(x: 427, y: 510, width: 43, height: 10), CasioF108WH.printWhite)
            Pointer(left: false).fill(CasioF108WH.printGrey).frame(width: 14.5, height: 6.5).offset(x: 482, y: 512)
        }
    }

    // MARK: LCD and WR badge

    private var lcd: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CasioF108WH.face)
                .frame(width: 337, height: 233).offset(x: 177, y: 270)
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CasioF108WH.rim, lineWidth: 3.5)
                .frame(width: 337, height: 233).offset(x: 177, y: 270)
            LCDPanel(
                display: F108WHDisplay.self, frame: CGRect(x: 181, y: 274, width: 329, height: 225), frameRadius: 13,
                surround: CasioF108WH.face, outline: .clear, outlineWidth: 0,
                glass: CGRect(x: 192, y: 288, width: 307.5, height: 202.5), glassRadius: 10, context: context,
                style: style)
        }
    }

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(CasioF108WH.face).frame(width: 106, height: 50).offset(
                x: 291, y: 512)
            RoundedRectangle(cornerRadius: 7).strokeBorder(CasioF108WH.printWhite, lineWidth: 2.5)
                .frame(width: 92.5, height: 40.5).offset(x: 297.5, y: 516.5)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.25)
                .placed(in: CGRect(x: 314, y: 527.5, width: 59.5, height: 19.5), color: CasioF108WH.printWhite)
        }
    }
}
