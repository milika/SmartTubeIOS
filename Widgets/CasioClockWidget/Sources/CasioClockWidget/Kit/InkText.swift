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

    /// The glyph outlines at 100 pt, y pointing down.
    static func outline(_ text: String, font: String, tracking: CGFloat) -> Path {
        BundledFonts.register()
        let ctFont = CTFontCreateWithName(font as CFString, 100, nil)
        let string = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTKernAttributeName as String): tracking * 100,
            ])
        let line = CTLineCreateWithAttributedString(string)
        let path = CGMutablePath()
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
                    glyphPath, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: -position.y))
            }
        }
        return Path(path)
    }
}

extension InkText {
    /// The text filling `box` on the canvas; `bold` thickens the strokes by that many points on
    /// each side (the box still holds the thickened ink).
    func placed(in box: CGRect, color: Color, bold: CGFloat = 0) -> some View {
        let inset = box.insetBy(dx: bold, dy: bold)
        return ZStack(alignment: .topLeading) {
            fill(color)
            if bold > 0 { stroke(color, style: StrokeStyle(lineWidth: 2 * bold, lineJoin: .round)) }
        }
        .frame(width: inset.width, height: inset.height)
        .offset(x: inset.minX, y: inset.minY)
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
