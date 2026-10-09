import SwiftUI

/// The DW-5600E face on its canvas (see CasioDW5600E for where the numbers come from).
struct DW5600EFace: View {
    let context: CasioFaceContext

    /// This watch's proportions of the SHOCK RESIST shield.
    private static let shield = ShockResistShield(cornerFraction: 0.08, shoulder: 0.62)

    private var style: LCDStyle { CasioDW5600E.lcd }
    /// The case extension: the face and its line grow by it, the LCD window by half; side labels
    /// and the print below move down to share the space.
    private var extra: CGFloat { CasioDW5600E.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            face
            topPrint
            sideLabels
            lcd.offset(y: extra / 4)
            bottomPrint.offset(y: extra)
        }
    }

    // MARK: Face

    /// The black face and its white line; the widget leaves the resin bezel (PROTECTION /
    /// G-SHOCK) out, like the GMW-B5000's.
    private var face: some View {
        ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 100, height: 108), bottomCut: CGSize(width: 90, height: 92), radius: 30)
                .fill(CasioDW5600E.face)
                .frame(width: 600, height: 520 + extra)
                .offset(x: 136, y: 108)
            CutCornerRect(cut: CGSize(width: 92, height: 100), bottomCut: CGSize(width: 80, height: 84), radius: 26)
                .stroke(CasioDW5600E.printWhite, lineWidth: 3)
                .frame(width: 558, height: 474 + extra)
                .offset(x: 157.5, y: 130.5)
        }
    }

    // MARK: Print

    private func ink(_ text: String, _ font: String, slant: CGFloat = 0) -> InkText {
        InkText(text: text, font: font, slant: slant)
    }

    private var topPrint: some View {
        let white = CasioDW5600E.printWhite
        return ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(in: CGRect(x: 373.5, y: 147, width: 126.5, height: 23), color: white, bold: 0.8)
            Pointer(left: true).fill(CasioDW5600E.blue).frame(width: 30, height: 10).offset(x: 286, y: 183)
            ink("ILLUMINATOR", CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 318, y: 179.5, width: 236, height: 17.5), color: CasioDW5600E.blue)
            Pointer(left: false).fill(CasioDW5600E.blue).frame(width: 32, height: 10).offset(x: 558.5, y: 183)
            ink("WATER 200M RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 302.5, y: 207.5, width: 272, height: 14), color: white, bold: 0.5)
        }
    }

    /// The side labels and dots: the upper pair moves with the LCD, the lower pair with the print
    /// below it.
    private var sideLabels: some View {
        let white = CasioDW5600E.printWhite
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                dot(x: 183.75, y: 251.25)
                ink("ADJUST", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 178, y: 269.5, width: 11.5, height: 67.5), angle: -90, color: white,
                        bold: 0.35)
                dot(x: 690.5, y: 246.25)
                ink("START·STOP", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 655.5, y: 264.5, width: 12.5, height: 111.5), angle: 90, color: white,
                        bold: 0.35)
                ink("LIGHT ON/OFF", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 684, y: 264, width: 12.5, height: 123.5), angle: 90, color: white,
                        bold: 0.35)
            }
            .offset(y: extra / 4)
            ZStack(alignment: .topLeading) {
                ink("MODE", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 176, y: 421, width: 12, height: 48.5), angle: -90, color: white, bold: 0.35)
                dot(x: 181.25, y: 488)
                ink("LIGHT", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 683.5, y: 417, width: 12, height: 49.5), angle: 90, color: white, bold: 0.35
                    )
                dot(x: 689.25, y: 485.25)
            }
            .offset(y: 3 * extra / 4)
        }
    }

    private var bottomPrint: some View {
        let white = CasioDW5600E.printWhite
        return ZStack(alignment: .topLeading) {
            ink("ELECTRO LUMINESCENT BACKLIGHT", CaseFont.archivoBlack, slant: 0.22)
                .placed(in: CGRect(x: 258.5, y: 513.5, width: 330, height: 13.5), color: white)
            Pointer(left: false).fill(white).frame(width: 16, height: 9).offset(x: 594.5, y: 516)
            ink("ALARM", CaseFont.michroma)
                .placed(in: CGRect(x: 258.5, y: 555.5, width: 89, height: 18), color: CasioDW5600E.gold, bold: 0.6)
            ink("CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 514.5, y: 554.5, width: 109.5, height: 18), color: CasioDW5600E.gold, bold: 0.6)
            shockResist
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioDW5600E.gold).frame(width: 14.5, height: 14.5).position(x: x, y: y)
    }

    /// The SHOCK RESIST badge: a gold outline with a red lower band.
    private var shockResist: some View {
        ZStack(alignment: .topLeading) {
            // The red band fills the badge below its two lines of text.
            Self.shield.fill(CasioDW5600E.red)
                .mask(
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 38)
                        Color.black
                    }
                )
                .frame(width: 134.5, height: 58).offset(x: 366, y: 538)
            Self.shield.stroke(CasioDW5600E.gold, lineWidth: 2.5).frame(
                width: 134.5, height: 58
            ).offset(x: 366, y: 538)
            InkText(text: "SHOCK", font: CaseFont.michroma)
                .placed(in: CGRect(x: 386, y: 546, width: 95, height: 12), color: CasioDW5600E.gold, bold: 0.5)
            InkText(text: "RESIST", font: CaseFont.michroma)
                .placed(in: CGRect(x: 386, y: 561, width: 95, height: 12), color: CasioDW5600E.gold, bold: 0.5)
        }
    }

    // MARK: LCD (module 3229)

    private var lcd: some View {
        let glass = CGRect(x: 240, y: 243.5, width: 392.5, height: 248 + extra / 2)
        return LCDPanel(
            display: Module3229Display.self, frame: CGRect(x: 229.5, y: 234, width: 413, height: 266 + extra / 2),
            frameRadius: 16, surround: CasioDW5600E.face, outline: CasioDW5600E.printWhite, outlineWidth: 2.5,
            glass: glass, glassRadius: 10, context: context, style: style)
    }
}
