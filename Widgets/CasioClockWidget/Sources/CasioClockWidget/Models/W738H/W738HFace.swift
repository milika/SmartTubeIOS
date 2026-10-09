import SwiftUI

/// The W-738H face on its canvas (see CasioW738H for where the numbers come from).
struct W738HFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioW738H.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            caseAndBezel
            printed
            lcd
            lightButton
        }
    }

    // MARK: Case, bezel, face

    private var caseAndBezel: some View {
        ZStack(alignment: .topLeading) {
            ink("VIBRATION ALARM", CaseFont.michroma)
                .placed(in: CGRect(x: 184, y: 47, width: 270, height: 19), color: CasioW738H.caseGrey, bold: 0.6)
            CutCornerRect(cut: CGSize(width: 70, height: 70), radius: 14)
                .fill(CasioW738H.bezel)
                .overlay(
                    CutCornerRect(cut: CGSize(width: 70, height: 70), radius: 14)
                        .stroke(CasioW738H.bezelEdge, lineWidth: 2)
                )
                .frame(width: 590, height: 484)
                .offset(x: 25, y: 91)
            CutCornerRect(cut: CGSize(width: 52, height: 88), bottomCut: CGSize(width: 56, height: 62), radius: 10)
                .fill(CasioW738H.face)
                .frame(width: 447, height: 413)
                .offset(x: 96, y: 120)
            CutCornerRect(cut: CGSize(width: 40, height: 77), bottomCut: CGSize(width: 46, height: 54), radius: 8)
                .stroke(CasioW738H.faceLine, lineWidth: 3)
                .frame(width: 419, height: 387)
                .offset(x: 110, y: 133)
        }
    }

    private func ink(_ text: String, _ font: String, slant: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, slant: slant)
    }

    private var printed: some View {
        let white = CasioW738H.printWhite
        return ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 272, y: 160.5, width: 95, height: 17), color: white, bold: 0.7)
            ink("10 YEAR BATTERY", CaseFont.michroma)
                .placed(in: CGRect(x: 215, y: 188.5, width: 210, height: 12), color: white, bold: 0.45)
            square(x: 125, y: 221)
            ink("ADJUST", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 124.5, y: 237, width: 10, height: 80.5), angle: -90, color: white, bold: 0.4)
            ink("MODE", CaseFont.michroma)
                .placed(vertical: CGRect(x: 124, y: 365, width: 10, height: 59), angle: -90, color: white, bold: 0.4)
            square(x: 124, y: 433)
            square(x: 505.5, y: 220.5)
            ink("SPLIT", CaseFont.michroma)
                .placed(vertical: CGRect(x: 504.5, y: 238, width: 10, height: 54), angle: 90, color: white, bold: 0.4)
            ink("START", CaseFont.michroma)
                .placed(vertical: CGRect(x: 505.5, y: 360, width: 10, height: 65.5), angle: 90, color: white, bold: 0.4)
            square(x: 507, y: 433)
            ink("TR", CaseFont.michroma)
                .placed(in: CGRect(x: 194.5, y: 463.5, width: 25.5, height: 10), color: white, bold: 0.4)
            ink("ST", CaseFont.michroma)
                .placed(in: CGRect(x: 273, y: 463, width: 26.5, height: 10.5), color: white, bold: 0.4)
            ink("AL", CaseFont.michroma)
                .placed(in: CGRect(x: 346, y: 463.5, width: 26, height: 9.5), color: white, bold: 0.4)
            ink("DT", CaseFont.michroma)
                .placed(in: CGRect(x: 418.5, y: 463.5, width: 26.5, height: 10), color: white, bold: 0.4)
            ink("WR100M", CaseFont.michroma)
                .placed(in: CGRect(x: 183, y: 488.5, width: 89, height: 10), color: white, bold: 0.4)
            RoundedRectangle(cornerRadius: 4)
                .stroke(white, lineWidth: 2)
                .frame(width: 61.5, height: 20.5)
                .offset(x: 289, y: 485)
            ink("WR", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 299, y: 489.5, width: 42.5, height: 12), color: white)
            ink("ILLUMINATOR", CaseFont.archivoBlack, slant: 0.2)
                .placed(in: CGRect(x: 366.5, y: 488.5, width: 108.5, height: 10), color: white)
        }
    }

    private func square(x: CGFloat, y: CGFloat) -> some View {
        Rectangle().fill(CasioW738H.printWhite).frame(width: 9, height: 9).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 152.5, y: 204, width: 333.5, height: 248)
        return LCDPanel(
            display: W738HDisplay.self, frame: CGRect(x: 150.5, y: 202, width: 337.5, height: 252), frameRadius: 20,
            surround: Color(white: 0.06), outline: Color(white: 0.30), outlineWidth: 1, glass: glass, glassRadius: 18,
            context: context, style: style)
    }

    // MARK: LIGHT button

    private var lightButton: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 18, height: 18), radius: 6)
                .fill(CasioW738H.caseBackground)
                .overlay(
                    CutCornerRect(cut: CGSize(width: 18, height: 18), radius: 6).stroke(
                        CasioW738H.bezelEdge, lineWidth: 1.5)
                )
                .frame(width: 290, height: 82)
                .offset(x: 175, y: 560)
            RoundedRectangle(cornerRadius: 8)
                .fill(CasioW738H.button)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.28), lineWidth: 1.5))
                .frame(width: 238, height: 48)
                .offset(x: 201, y: 586)
            ink("LIGHT", CaseFont.michroma)
                .placed(in: CGRect(x: 265, y: 603.5, width: 114, height: 14), color: CasioW738H.caseGrey, bold: 0.6)
        }
    }
}
