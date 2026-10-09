import SwiftUI

/// The W-59 face on its canvas (see CasioW59 for where the numbers come from).
struct W59Face: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioW59.lcd }
    /// The case extension: lines grow by it, the LCD window by half; the print below moves down.
    private var extra: CGFloat { CasioW59.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            lines
            topPrint
            lcd.offset(y: extra / 4)
            bottomPrint.offset(y: extra)
        }
    }

    // MARK: Lines

    private var lines: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 34, height: 44), bottomCut: CGSize(width: 22, height: 22), radius: 16)
                .fill(CasioW59.plate)
                .frame(width: 466, height: 410.5 + extra)
                .offset(x: 37.75, y: 26)
            // Outer white line: near-diagonal cut corners. Blue band: wide curves, wider at the bottom.
            CutCornerRect(cut: CGSize(width: 62, height: 66), bottomCut: CGSize(width: 58, height: 48), radius: 26)
                .stroke(CasioW59.line, lineWidth: 2.5)
                .frame(width: 442, height: 386.5 + extra)
                .offset(x: 49.75, y: 38)
            UnevenRoundedRectangle(
                topLeadingRadius: 40, bottomLeadingRadius: 55, bottomTrailingRadius: 55, topTrailingRadius: 40,
                style: .continuous
            )
            .stroke(CasioW59.blue, lineWidth: 10)
            .frame(width: 406.5, height: 263.25 + extra)
            .offset(x: 68, y: 96.25)
        }
    }

    // MARK: Print

    private func ink(_ text: String, _ font: String, slant: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, slant: slant)
    }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 116.5, y: 56, width: 111.5, height: 21.5), color: CasioW59.printWhite, bold: 0.8)
            ink("ALARM CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 270.5, y: 57.5, width: 154.5, height: 14.5), color: CasioW59.gold, bold: 0.3)
            marker(x: 110, y: 114)
            ink("LIGHT", CaseFont.michroma)
                .placed(in: CGRect(x: 134, y: 113, width: 40.5, height: 10.5), color: CasioW59.labelWhite, bold: 0.2)
            marker(x: 110.5, y: 130.5)
            ink("MODE", CaseFont.michroma)
                .placed(in: CGRect(x: 134.5, y: 129.5, width: 42, height: 10.5), color: CasioW59.labelWhite, bold: 0.2)
            ink("24HR", CaseFont.michroma)
                .placed(in: CGRect(x: 211, y: 129, width: 37.5, height: 10.5), color: CasioW59.labelWhite, bold: 0.2)
            marker(x: 255, y: 130)
            ink("Lithium", CaseFont.saira)
                .placed(in: CGRect(x: 340, y: 119, width: 65.5, height: 12), color: CasioW59.gold)
        }
    }

    /// The small gold bars beside the button labels.
    private func marker(x: CGFloat, y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(CasioW59.gold).frame(width: 18, height: 8.5).offset(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("WATER RESIST", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 121, y: 379.5, width: 201, height: 13), color: CasioW59.gold)
            Rectangle().fill(CasioW59.red).frame(width: 220, height: 6.5).offset(x: 111, y: 399)
            ink("50M", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 340, y: 379, width: 95.5, height: 25), color: CasioW59.red)
        }
    }

    // MARK: LCD (module 590)

    private var lcd: some View {
        let glass = CGRect(x: 103, y: 160.5, width: 336.5, height: 163.5 + extra / 2)
        return ZStack(alignment: .topLeading) {
            LCDWindow(
                frame: CGRect(x: 89.5, y: 147, width: 362.5, height: 190.75 + extra / 2), frameRadius: 16,
                surround: Color(white: 0.09), outline: CasioW59.line, outlineWidth: 2,
                glass: glass, glassRadius: 9, backlit: context.backlit, style: style)
            Module590Display.placed(in: glass, context: context, style: style)
        }
    }
}
