import CoreText
import SwiftUI

/// Printed text drawn as its glyph outlines, stretched so its ink fills a box exactly: a label is
/// placed with the ink box measured on the reference photo instead of a font size and position
/// tuned by hand. For fixed print only (the box fits one string, not changing text).
struct InkText: Shape {
    let text: String
    /// PostScript name of a bundled font.
    let font: String
    /// Extra space between letters, in ems.
    var tracking: CGFloat = 0
    /// Italic slant for fonts without an italic face (0.2 leans the tops 0.2 × height right).
    var slant: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let outline = Self.outline(text, font: font, tracking: tracking)
            .applying(CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: 0, ty: 0))
        let bounds = outline.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        return outline.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / bounds.width, y: rect.height / bounds.height)
                .translatedBy(x: -bounds.minX, y: -bounds.minY))
    }

    /// The glyph outlines at 100 pt, y pointing down. A middle dot "·" is drawn as a round dot a
    /// third of the cap height across with space on both sides, as the watches print it (the case
    /// fonts' own middle dots are small and tight: "12·24H" read as "12:24H").
    static func outline(_ text: String, font: String, tracking: CGFloat) -> Path {
        BundledFonts.register()
        let ctFont = CTFontCreateWithName(font as CFString, 100, nil)
        let capHeight = CTFontGetCapHeight(ctFont)
        let diameter = 0.33 * capHeight, gap = 0.2 * capHeight
        let path = CGMutablePath()
        var x: CGFloat = 0
        for (index, segment) in text.components(separatedBy: "·").enumerated() {
            if index > 0 {
                x += gap
                path.addEllipse(
                    in: CGRect(x: x, y: -(capHeight + diameter) / 2, width: diameter, height: diameter))
                x += diameter + gap
            }
            x += addGlyphs(of: segment, font: ctFont, tracking: tracking, at: x, to: path)
        }
        return Path(path)
    }

    /// Adds `text`'s glyph outlines starting at `x` (y pointing down); returns the advance.
    private static func addGlyphs(
        of text: String, font ctFont: CTFont, tracking: CGFloat, at x: CGFloat, to path: CGMutablePath
    )
        -> CGFloat
    {
        guard !text.isEmpty else { return 0 }
        let string = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTKernAttributeName as String): tracking * 100,
            ])
        let line = CTLineCreateWithAttributedString(string)
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont  // swiftlint:disable:this force_cast
            for (glyph, position) in zip(glyphs, positions) {
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                path.addPath(
                    glyphPath,
                    transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + position.x, ty: -position.y))
            }
        }
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

extension InkText {
    /// The text filling `box` on the canvas; `bold` thickens the strokes by that many points on
    /// each side (the box still holds the thickened ink). `barBold`, when smaller, thickens the
    /// horizontal bars less than the stems: heavy print bolded equally all round closes the narrow
    /// gaps between bars (the F-91W's S read as an 8, "CA8IO").
    func placed(in box: CGRect, color: Color, bold: CGFloat = 0, barBold: CGFloat? = nil) -> some View {
        let barBold = min(barBold ?? bold, bold)
        return Group {
            if barBold < bold {
                Thickened(ink: self, dx: bold, dy: barBold).fill(color)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            } else {
                let inset = box.insetBy(dx: bold, dy: bold)
                ZStack(alignment: .topLeading) {
                    fill(color)
                    if bold > 0 { stroke(color, style: StrokeStyle(lineWidth: 2 * bold, lineJoin: .round)) }
                }
                .frame(width: inset.width, height: inset.height)
                .offset(x: inset.minX, y: inset.minY)
            }
        }
    }

    /// Vertical text: `box` is its ink box on the canvas, `angle` -90 reads upwards, 90 downwards.
    func placed(vertical box: CGRect, angle: Double, color: Color, bold: CGFloat = 0) -> some View {
        let inset = box.insetBy(dx: bold, dy: bold)
        return ZStack(alignment: .topLeading) {
            fill(color)
            if bold > 0 { stroke(color, style: StrokeStyle(lineWidth: 2 * bold, lineJoin: .round)) }
        }
        .frame(width: inset.height, height: inset.width)
        .rotationEffect(.degrees(angle))
        .position(x: inset.midX, y: inset.midY)
    }
}

/// An InkText's glyphs thickened by `dx` points sideways and `dy` vertically (dy < dx), as one
/// path: the glyphs fill the rect less those margins, and the thickened ink fills it exactly.
private struct Thickened: Shape {
    let ink: InkText
    let dx: CGFloat
    let dy: CGFloat

    func path(in rect: CGRect) -> Path {
        let glyphs = ink.path(in: rect.insetBy(dx: dx, dy: dy)).cgPath
        // Round strokes thicken by dy all round; copies shifted sideways make up the rest of dx.
        let round =
            dy > 0
            ? glyphs.union(glyphs.copy(strokingWithWidth: 2 * dy, lineCap: .round, lineJoin: .round, miterLimit: 10))
            : glyphs
        var thick = round
        let extra = dx - dy
        let steps = max(1, Int((extra / 0.25).rounded(.up)))
        for step in 1...steps {
            let shift = extra * CGFloat(step) / CGFloat(steps)
            for sign: CGFloat in [-1, 1] {
                var move = CGAffineTransform(translationX: sign * shift, y: 0)
                if let moved = round.copy(using: &move) { thick = thick.union(moved) }
            }
        }
        return Path(thick)
    }
}
