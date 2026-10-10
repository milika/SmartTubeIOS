import SwiftUI

/// The F-91W face on its canvas (see CasioF91W for where the numbers come from).
struct F91WFace: View {
    let context: CasioFaceContext

    private var style: LCDStyle { CasioF91W.lcd }
    /// The case extension (see CasioF91W.caseExtension): the frame lines grow by it, the LCD
    /// window by half of it, and the groups below move down to share the space evenly.
    private var stretch: CaseExtension { CaseExtension(amount: CasioF91W.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bezel
            printedFace
            lcd
        }
    }

    // MARK: Bezel and frame lines

    private var bezel: some View {
        ZStack(alignment: .topLeading) {
            // Thin outer blue line, wide blue band, white line framing the printed face; all three
            // are octagons with the watch's cut corners.
            frameLine(
                CGRect(x: 23.5, y: 31.5, width: 548.5, height: 472 + stretch.caseGrowth), 3, radius: 24, CasioF91W.blue)
            frameLine(
                CGRect(x: 36, y: 45.5, width: 520.5, height: 445 + stretch.caseGrowth), 10.5, radius: 22, CasioF91W.blue
            )
            frameLine(
                CGRect(x: 50, y: 60, width: 492, height: 417 + stretch.caseGrowth), 2, radius: 18, CasioF91W.silver)
        }
    }

    /// A frame line `lineWidth` wide stroked along the given centerline rectangle.
    private func frameLine(_ centerline: CGRect, _ lineWidth: CGFloat, radius: CGFloat, _ color: Color) -> some View {
        CutCornerRect(cut: CGSize(width: 40, height: 64), radius: radius)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: centerline.width, height: centerline.height)
            .offset(x: centerline.minX, y: centerline.minY)
    }

    // MARK: Printed text and bars

    private var printedFace: some View {
        ZStack(alignment: .topLeading) {
            // CASIO / F-91W (ink boxes measured on the photo)
            ink(
                "CASIO", CGRect(x: 132, y: 81.5, width: 130, height: 23.5), CasioF91W.printWhite, bold: 2.0,
                barBold: 1.0)
            // F-91W is widely spaced on the watch: each glyph in its measured box.
            ForEach(Array(Self.modelName.enumerated()), id: \.offset) { _, glyph in
                InkText(text: glyph.text, font: CaseFont.archivoBlack, slant: 0.21)
                    .placed(in: glyph.box, color: CasioF91W.gold)
            }
            bar(x: 70, y: 123.5, width: 453, height: 9)

            // ◀ LIGHT   ALARM  CHRONOGRAPH
            Pointer(left: true).fill(CasioF91W.red).frame(width: 21, height: 7).position(x: 96.75, y: 157.75)
            ink("LIGHT", CGRect(x: 117.5, y: 152.5, width: 54.5, height: 10), CasioF91W.printWhite, bold: 0.3)
            InkText(text: "ALARM", font: CaseFont.saira)
                .placed(in: CGRect(x: 226.5, y: 146, width: 81.5, height: 16.5), color: CasioF91W.gold, bold: 0.3)
            InkText(text: "CHRONOGRAPH", font: CaseFont.saira)
                .placed(in: CGRect(x: 321, y: 146, width: 179.5, height: 16.5), color: CasioF91W.gold, bold: 0.3)

        }
        .overlay(alignment: .topLeading) { bottomPrint.band(.bottom, of: stretch) }
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            // ◀ MODE   ALARM  ON · OFF / 24HR ▶
            Pointer(left: true).fill(CasioF91W.red).frame(width: 20, height: 6.5).position(x: 98, y: 404.5)
            ink("MODE", CGRect(x: 118, y: 398.5, width: 58.5, height: 10.5), CasioF91W.printWhite, bold: 0.3)
            ink("ALARM", CGRect(x: 243.5, y: 398.5, width: 70.5, height: 10.5), CasioF91W.printWhite, bold: 0.3)
            ink("ON", CGRect(x: 328.5, y: 398.5, width: 28.5, height: 10.5), CasioF91W.printWhite, bold: 0.3)
            Circle().fill(CasioF91W.printWhite).frame(width: 3.5, height: 3.5).offset(x: 362.5, y: 401.5)
            ink("OFF", CGRect(x: 370, y: 398, width: 36, height: 11), CasioF91W.printWhite, bold: 0.3)
            ink("/", CGRect(x: 409.5, y: 398.5, width: 8, height: 10), CasioF91W.printWhite, bold: 0.3)
            ink("24HR", CGRect(x: 422.5, y: 398, width: 52.5, height: 11), CasioF91W.printWhite, bold: 0.3)
            Pointer(left: false).fill(CasioF91W.red).frame(width: 20.5, height: 7).position(x: 497.25, y: 404.25)

            // WATER [WR] RESIST
            bar(x: 70, y: 419, width: 144.5, height: 5.5)
            bar(x: 375, y: 419, width: 148.5, height: 5.5)
            // The WR box: round top corners, cut bottom corners.
            CutCornerRect(cut: CGSize(width: 11, height: 11), bottomCut: CGSize(width: 15, height: 15), radius: 8)
                .stroke(CasioF91W.blue, lineWidth: 3.75)
                .frame(width: 140.6, height: 47)
                .offset(x: 226.6, y: 417.6)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.21)
                .placed(in: CGRect(x: 249, y: 430, width: 97, height: 24), color: CasioF91W.red)
            ink(
                "WATER", CGRect(x: 102.5, y: 435, width: 106.5, height: 15.5), CasioF91W.printWhite, bold: 1.2,
                barBold: 0.7)
            ink(
                "RESIST", CGRect(x: 384, y: 434.5, width: 109.5, height: 16), CasioF91W.printWhite, bold: 1.2,
                barBold: 0.7)
            InkText(text: "u", font: CaseFont.saira)
                .placed(
                    in: CGRect(x: 456.5, y: 460.5, width: 5.5, height: 6.5), color: CasioF91W.printWhite.opacity(0.85))
        }
    }

    private static let modelName: [(text: String, box: CGRect)] = [
        ("F", CGRect(x: 338.5, y: 83.5, width: 22.5, height: 19)),
        ("-", CGRect(x: 365, y: 90.5, width: 11.5, height: 5.5)),
        ("9", CGRect(x: 382.5, y: 83.5, width: 21.5, height: 18.5)),
        ("1", CGRect(x: 410, y: 83.5, width: 12, height: 19)),
        ("W", CGRect(x: 428.5, y: 83.5, width: 33, height: 19)),
    ]

    private func ink(_ text: String, _ box: CGRect, _ color: Color, bold: CGFloat, barBold: CGFloat? = nil) -> some View
    {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: color, bold: bold, barBold: barBold)
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 6) -> some View {
        Rectangle().fill(CasioF91W.blue).frame(width: width, height: height).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(
            x: 100.5, y: 185 + stretch.offset(.display), width: 391, height: 192.5 + stretch.windowGrowth)
        // Silver outline, dark surround, grey-green glass, and the module 593 display.
        return LCDPanel(
            display: Module593Display.self,
            frame: CGRect(x: 89, y: 174 + stretch.offset(.display), width: 414.5, height: 214 + stretch.windowGrowth),
            outline: CasioF91W.silver,
            glass: glass, context: context, style: style)
    }
}
