import SwiftUI

/// The W-800H face on its canvas (see CasioW800H for where the numbers come from).
struct W800HFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioW800H.lcd }

    var body: some View {
        ZStack(alignment: .topLeading) {
            caseShape
            lcd
            // The print after the window: ADJUST reaches into the window's dark surround.
            printed
        }
    }

    // MARK: Case, bezel, face

    private var caseShape: some View {
        ZStack(alignment: .topLeading) {
            engraved
            CutCornerRect(cut: CGSize(width: 58, height: 58), radius: 18)
                .fill(CasioW800H.bezel)
                .overlay(
                    CutCornerRect(cut: CGSize(width: 58, height: 58), radius: 18).stroke(
                        CasioW800H.resinLight, lineWidth: 3)
                )
                .frame(width: 436, height: 448)
                .offset(x: 72, y: 110)
            CutCornerRect(cut: CGSize(width: 40, height: 40), radius: 12)
                .fill(CasioW800H.plate)
                .overlay(
                    CutCornerRect(cut: CGSize(width: 40, height: 40), radius: 12).stroke(
                        CasioW800H.plateEdge, lineWidth: 1.5)
                )
                .frame(width: 374, height: 380)
                .offset(x: 101, y: 141)
            CutCornerRect(cut: CGSize(width: 30, height: 30), radius: 9)
                .stroke(CasioW800H.printWhite, lineWidth: 1.6)
                .frame(width: 340, height: 351)
                .offset(x: 122.25, y: 161.75)
        }
    }

    /// ILLUMINATOR with its two arrows, moulded into the resin (dark, with a light lower edge).
    private var engraved: some View {
        ZStack(alignment: .topLeading) {
            Group {
                InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                    .placed(
                        in: CGRect(x: 195.5, y: 77, width: 195, height: 16), color: CasioW800H.resinLight.opacity(0.9))
                Pointer(left: true).fill(CasioW800H.resinLight.opacity(0.9)).frame(width: 25, height: 10.5).offset(
                    x: 169.5, y: 81)
                Pointer(left: false).fill(CasioW800H.resinLight.opacity(0.9)).frame(width: 26.5, height: 10.5).offset(
                    x: 392, y: 80)
            }
            .offset(y: 1.2)
            InkText(text: "ILLUMINATOR", font: CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 195.5, y: 77, width: 195, height: 16), color: CasioW800H.engraved)
            Pointer(left: true).fill(CasioW800H.engraved).frame(width: 25, height: 10.5).offset(x: 169.5, y: 81)
            Pointer(left: false).fill(CasioW800H.engraved).frame(width: 26.5, height: 10.5).offset(x: 392, y: 80)
        }
    }

    private func ink(_ text: String, _ font: String) -> InkText { InkText(text: text, font: font) }

    private var printed: some View {
        let white = CasioW800H.printWhite
        return ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 173, y: 173, width: 96, height: 17.5), color: white, bold: 0.8)
            ink("10 YEAR BATTERY", CaseFont.saira)
                .placed(in: CGRect(x: 285.5, y: 178.5, width: 124, height: 13), color: white, bold: 0.5)
            ink("ADJUST", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 129.5, y: 222.5, width: 10, height: 80.5), angle: -90, color: white, bold: 0.3)
            ink("MODE", CaseFont.michroma)
                .placed(vertical: CGRect(x: 128, y: 374, width: 9, height: 64.5), angle: -90, color: white, bold: 0.3)
            ink("LIGHT", CaseFont.michroma)
                .placed(
                    vertical: CGRect(x: 438.5, y: 225.5, width: 8.5, height: 61), angle: 90, color: white, bold: 0.3)
            // 12/24H in three pieces: Michroma's slash drops below the baseline, the watch's doesn't.
            ink("12", CaseFont.michroma)
                .placed(vertical: CGRect(x: 436.5, y: 366, width: 9, height: 20), angle: 90, color: white, bold: 0.3)
            ink("/", CaseFont.michroma)
                .placed(vertical: CGRect(x: 436.5, y: 390.5, width: 9, height: 9), angle: 90, color: white, bold: 0.3)
            ink("24H", CaseFont.michroma)
                .placed(vertical: CGRect(x: 436.5, y: 402, width: 9, height: 40.5), angle: 90, color: white, bold: 0.3)
            ink("WATER", CaseFont.michroma)
                .placed(in: CGRect(x: 172, y: 476, width: 72, height: 13.5), color: white, bold: 0.6)
            CutCornerRect(cut: CGSize(width: 8, height: 8), radius: 4)
                .stroke(white, lineWidth: 2.2)
                .frame(width: 67, height: 30)
                .offset(x: 252, y: 466.5)
            ink("100M", CaseFont.michroma)
                .placed(in: CGRect(x: 259, y: 474.5, width: 53, height: 14), color: white, bold: 0.8)
            ink("RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 326.5, y: 478.5, width: 74.5, height: 13.5), color: white, bold: 0.6)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 140, y: 202.5, width: 294.5, height: 259)
        return LCDPanel(
            display: W800HDisplay.self, frame: CGRect(x: 137, y: 199.5, width: 298.5, height: 265), frameRadius: 20,
            surround: Color(white: 0.06), outline: .clear, outlineWidth: 0, glass: glass, glassRadius: 18,
            context: context, style: style)
    }
}
