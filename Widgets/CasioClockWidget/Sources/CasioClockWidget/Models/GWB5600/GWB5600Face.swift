import SwiftUI

/// The GW-B5600 face on its canvas (see CasioGWB5600 for where the numbers come from).
struct GWB5600Face: View {
    let context: CasioFaceContext

    /// This watch's proportions of the SHOCK RESIST shield.
    private static let shield = ShockResistShield(cornerFraction: 0.1, shoulder: 0.68)

    private var style: LCDStyle { CasioGWB5600.lcd }
    /// The case extension: face and panel grow by it, the LCD window by half; side labels and the
    /// print below move down.
    private var extra: CGFloat { CasioGWB5600.caseExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            faceAndPanel
            topPrint
            sideLabels
            lcd.offset(y: extra / 4)
            bottomPrint.offset(y: extra)
        }
    }

    // MARK: Face, camouflage, panel

    private var faceAndPanel: some View {
        let faceShape = CutCornerRect(cut: CGSize(width: 70, height: 70), radius: 30)
        return ZStack(alignment: .topLeading) {
            faceShape.fill(CasioGWB5600.face)
                .overlay(Camouflage().fill(CasioGWB5600.camo).clipShape(faceShape))
                .frame(width: 609, height: 535 + extra)
                .offset(x: 8, y: 12)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(CasioGWB5600.panel)
                .frame(width: 483, height: 378 + extra)
                .offset(x: 72, y: 79)
        }
    }

    // MARK: Print

    private func ink(_ text: String, _ font: String) -> InkText { InkText(text: text, font: font) }

    private var topPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("CASIO", CaseFont.michroma)
                .placed(
                    in: CGRect(x: 250.5, y: 41, width: 118, height: 23.5), color: CasioGWB5600.printWhite, bold: 0.8)
            ink("TOUGH SOLAR", CaseFont.michroma)
                .placed(in: CGRect(x: 212.5, y: 108.5, width: 197, height: 13.5), color: CasioGWB5600.mint, bold: 0.6)
        }
    }

    /// ADJUST / MODE read upwards on the left, LIGHT / RECEIVING downwards on the right, with dots.
    private var sideLabels: some View {
        let white = CasioGWB5600.printWhite
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                dot(x: 40.75, y: 166.75)
                ink("ADJUST", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 33, y: 187.5, width: 14, height: 76.5), angle: -90, color: white, bold: 0.4)
                dot(x: 583, y: 160.75)
                ink("LIGHT", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 577, y: 177.5, width: 14.5, height: 60), angle: 90, color: white, bold: 0.4)
            }
            .offset(y: extra / 4)
            ZStack(alignment: .topLeading) {
                ink("MODE", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 34.5, y: 324, width: 14.5, height: 59.5), angle: -90, color: white,
                        bold: 0.4)
                dot(x: 41.25, y: 399.25)
                ink("RECEIVING", CaseFont.michroma)
                    .placed(
                        vertical: CGRect(x: 577, y: 278.5, width: 15, height: 100.5), angle: 90, color: white, bold: 0.4
                    )
                dot(x: 585, y: 395)
            }
            .offset(y: 3 * extra / 4)
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(CasioGWB5600.printWhite).frame(width: 11.5, height: 11.5).position(x: x, y: y)
    }

    private var bottomPrint: some View {
        ZStack(alignment: .topLeading) {
            ink("Bluetooth", CaseFont.saira)
                .placed(in: CGRect(x: 267.5, y: 432, width: 89, height: 21), color: CasioGWB5600.mint, bold: 0.5)
            ink("ALARM", CaseFont.michroma)
                .placed(in: CGRect(x: 159.5, y: 463, width: 82, height: 16.5), color: CasioGWB5600.mint, bold: 0.7)
            ink("CHRONO", CaseFont.michroma)
                .placed(in: CGRect(x: 383, y: 463, width: 96, height: 15), color: CasioGWB5600.mint, bold: 0.7)
            Self.shield.fill(CasioGWB5600.face).frame(width: 104, height: 53)
                .offset(x: 260, y: 465.5)
            Self.shield.stroke(CasioGWB5600.printWhite, lineWidth: 2.5)
                .frame(width: 104, height: 53).offset(
                    x: 260, y: 465.5)
            ink("SHOCK", CaseFont.michroma)
                .placed(in: CGRect(x: 275, y: 474, width: 74, height: 9.5), color: CasioGWB5600.printWhite, bold: 0.4)
            ink("RESIST", CaseFont.michroma)
                .placed(in: CGRect(x: 275, y: 487, width: 74, height: 9.5), color: CasioGWB5600.printWhite, bold: 0.4)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let glass = CGRect(x: 115, y: 154, width: 396, height: 258 + extra / 2)
        return ZStack(alignment: .topLeading) {
            LCDWindow(
                frame: CGRect(x: 104, y: 139, width: 418, height: 283 + extra / 2), frameRadius: 26,
                surround: Color(white: 0.02), outline: .clear, outlineWidth: 0,
                glass: glass, glassRadius: 16, backlit: context.backlit, style: style)
            GWB5600Display.placed(in: glass, context: context, style: style)
        }
    }
}

/// A stand-in for the face's camouflage print: fixed, irregular rounded blobs (the same on every
/// render), drawn in unit coordinates and scaled to the face.
private struct Camouflage: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var seed: UInt64 = 0x5600
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<150 {
            let center = CGPoint(x: rect.minX + next() * rect.width, y: rect.minY + next() * rect.height)
            let length = rect.width * (0.04 + 0.07 * next())
            let thickness = rect.height * (0.015 + 0.025 * next())
            let blob = Path(
                roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
                cornerRadius: thickness / 2)
            let angle = (next() - 0.5) * 0.5
            path.addPath(
                blob.applying(
                    CGAffineTransform(rotationAngle: angle).concatenating(
                        CGAffineTransform(translationX: center.x, y: center.y))))
        }
        return path
    }
}
