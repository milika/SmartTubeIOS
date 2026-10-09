import SwiftUI

/// The A700W face on its canvas (see CasioA700W for where the numbers come from), in the colours and
/// proportions of one of its versions: the steel A700WE with a grey plate and boxed coloured labels,
/// or the negative version with a black face, a cyan line and cyan print.
struct A700WFace<Display: LCDModuleDisplay>: View {
    let context: CasioFaceContext
    let palette: A700WPalette
    let layout: A700WGeometry
    let display: Display.Type
    let style: LCDStyle

    /// The case extension: band, line and plate grow by it, the LCD window by half; the print
    /// around the window moves with its edges and the print below moves down.
    private var stretch: CaseExtension { CaseExtension(amount: CasioA700W.caseExtension) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bandAndPlate
            InkText(text: "CASIO", font: CaseFont.michroma).placed(in: layout.casio, color: palette.logo, bold: 0.9)
            waterResist.band(.upperSides, of: stretch)
            window.band(.display, of: stretch)
            buttonLabels.band(.lowerSides, of: stretch)
            InkText(text: "ALARM CHRONOGRAPH", font: CaseFont.michroma)
                .placed(in: layout.alarmChronograph, color: palette.print, bold: 0.6)
                .band(.bottom, of: stretch)
        }
    }

    // MARK: Band, line and plate

    private var bandAndPlate: some View {
        let line = layout.line, width = layout.lineWidth
        return ZStack(alignment: .topLeading) {
            CutCornerRect(cut: CGSize(width: 46, height: 50), radius: 14)
                .fill(palette.band)
                .frame(width: layout.band.width, height: layout.band.height + stretch.caseGrowth)
                .offset(x: layout.band.minX, y: layout.band.minY)
            if layout.lineFilled {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.silver)
                    .frame(width: line.width, height: line.height + stretch.caseGrowth)
                    .offset(x: line.minX, y: line.minY)
                RoundedRectangle(cornerRadius: 24 - width, style: .continuous)
                    .fill(palette.plate)
                    .frame(width: line.width - 2 * width, height: line.height - 2 * width + stretch.caseGrowth)
                    .offset(x: line.minX + width, y: line.minY + width)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(palette.silver, lineWidth: width)
                    .frame(width: line.width, height: line.height + stretch.caseGrowth)
                    .offset(x: line.minX, y: line.minY)
            }
        }
    }

    // MARK: Print (ink boxes measured on the image)

    private var waterResist: some View {
        ZStack(alignment: .topLeading) {
            InkText(text: "WATER", font: CaseFont.michroma).placed(in: layout.water, color: palette.print, bold: 0.5)
            RoundedRectangle(cornerRadius: 7).stroke(palette.print, lineWidth: 2)
                .frame(width: layout.wrBox.width - 2, height: layout.wrBox.height - 2)
                .offset(x: layout.wrBox.minX + 1, y: layout.wrBox.minY + 1)
            InkText(text: "WR", font: CaseFont.sairaExpanded, slant: 0.2).placed(in: layout.wr, color: palette.print)
            InkText(text: "RESIST", font: CaseFont.michroma).placed(in: layout.resist, color: palette.print, bold: 0.5)
        }
    }

    private var buttonLabels: some View {
        ZStack(alignment: .topLeading) {
            square(layout.lightSquare)
            InkText(text: "LIGHT", font: CaseFont.michroma).placed(in: layout.light, color: palette.print, bold: 0.4)
            square(layout.modeSquare)
            InkText(text: "MODE", font: CaseFont.michroma).placed(in: layout.mode, color: palette.print, bold: 0.4)
            InkText(text: "START·STOP/12·24H", font: CaseFont.michroma)
                .placed(in: layout.startStop, color: palette.print, bold: 0.4)
            square(layout.rightSquare)
        }
    }

    private func square(_ box: CGRect) -> some View {
        Rectangle().fill(palette.print).frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
    }

    // MARK: The LCD window: outline, labels strip, glass

    private var window: some View {
        let growth = stretch.windowGrowth
        let frame = layout.frame, glass = layout.glass
        return ZStack(alignment: .topLeading) {
            LCDPanel(
                display: display,
                frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + growth),
                frameRadius: 14, surround: palette.surround, outline: palette.frame ?? palette.surround,
                outlineWidth: palette.frame == nil ? 0 : 4.5,
                glass: CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: glass.height + growth),
                glassRadius: 6, context: context, style: style)
            if let outline = palette.frame, let box = palette.labelBox {
                // The A700WE's outline is double: a dark line, then a second light one inside it;
                // a light line separates the labels from the glass.
                RoundedRectangle(cornerRadius: 10).stroke(box, lineWidth: 2)
                    .frame(width: frame.width - 13, height: frame.height - 13 + growth)
                    .offset(x: frame.minX + 6.5, y: frame.minY + 6.5)
                RoundedRectangle(cornerRadius: 8).stroke(outline, lineWidth: 2.5)
                    .frame(width: frame.width - 20, height: frame.height - 20 + growth)
                    .offset(x: frame.minX + 10, y: frame.minY + 10)
                Rectangle().fill(palette.surround.opacity(0.9)).frame(width: glass.width, height: 6)
                    .offset(x: glass.minX, y: glass.minY - 6.5)
            }
            labelStrip
        }
    }

    private var labelStrip: some View {
        ZStack(alignment: .topLeading) {
            if let box = palette.labelBox {
                Rectangle().fill(box).frame(width: 355, height: 19).offset(x: 127.5, y: 229)
                ForEach([205.5, 289.5, 375.5], id: \.self) { x in
                    Rectangle().fill(palette.separator).frame(width: 6, height: 19).offset(x: x, y: 229)
                }
            }
            ForEach(Array(["ALARM", "SIG", "SPL", "CHRONO"].enumerated()), id: \.offset) { index, text in
                InkText(text: text, font: CaseFont.michroma)
                    .placed(in: layout.labels[index], color: palette.labels[index], bold: 0.4)
            }
        }
    }
}

/// A version's colours.
struct A700WPalette {
    let band: Color
    /// CASIO on the band.
    let logo: Color
    let silver: Color
    let plate: Color
    let print: Color
    /// The window's outline lines (nil: no outline).
    let frame: Color?
    /// Between the outline and the glass.
    let surround: Color
    /// The black boxes behind ALARM / SIG / SPL / CHRONO and the bars between them (nil: none).
    let labelBox: Color?
    let separator: Color
    /// ALARM, SIG, SPL and CHRONO.
    let labels: [Color]
}

/// A version's measured geometry (canvas points, before the case extension).
struct A700WGeometry {
    let band: CGRect
    /// The silver line around the plate: its outer rectangle and width; filled (A700WE, with the
    /// grey plate inside) or stroked (negative).
    let line: CGRect
    let lineWidth: CGFloat
    let lineFilled: Bool
    let casio: CGRect
    let water: CGRect
    let wrBox: CGRect
    let wr: CGRect
    let resist: CGRect
    let frame: CGRect
    let glass: CGRect
    let lightSquare: CGRect
    let light: CGRect
    let modeSquare: CGRect
    let mode: CGRect
    let startStop: CGRect
    let rightSquare: CGRect
    let alarmChronograph: CGRect
    /// ALARM, SIG, SPL and CHRONO.
    let labels: [CGRect]
}
