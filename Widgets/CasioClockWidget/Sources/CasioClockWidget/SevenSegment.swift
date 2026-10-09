import SwiftUI

// MARK: - Seven-segment LCD digits
//
// Drawn with shapes rather than a font so the package needs no bundled font file.
// Unlit segments stay faintly visible, like a real reflective LCD.

/// Segments a…g in the usual order: top, top-right, bottom-right, bottom, bottom-left,
/// top-left, middle.
private let segmentsForDigit: [Int: [Bool]] = [
    0: [true, true, true, true, true, true, false],
    1: [false, true, true, false, false, false, false],
    2: [true, true, false, true, true, false, true],
    3: [true, true, true, true, false, false, true],
    4: [false, true, true, false, false, true, true],
    5: [true, false, true, true, false, true, true],
    6: [true, false, true, true, true, true, true],
    7: [true, true, true, false, false, false, false],
    8: [true, true, true, true, true, true, true],
    9: [true, true, true, true, false, true, true],
]

struct SevenSegmentDigit: View {
    /// nil = blank (e.g. the leading digit of a one-digit hour).
    let digit: Int?
    let color: Color

    var body: some View {
        Canvas { context, size in
            let lit = digit.flatMap { segmentsForDigit[$0] } ?? Array(repeating: false, count: 7)
            for (index, path) in Self.segmentPaths(in: size).enumerated() {
                context.fill(path, with: .color(color.opacity(lit[index] ? 1 : 0.07)))
            }
        }
    }

    /// Slightly slanted segments with pointed ends.
    static func segmentPaths(in size: CGSize) -> [Path] {
        let w = size.width, h = size.height
        let t = min(w, h) * 0.17  // segment thickness
        let gap = t * 0.18
        let slant = w * 0.08  // italic lean, like the watch's digits

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            // Shift x by the slant, more at the top.
            CGPoint(x: x + slant * (1 - y / h), y: y)
        }
        func horizontal(_ y: CGFloat) -> Path {
            var p = Path()
            let x0 = t / 2 + gap, x1 = w - slant - t / 2 - gap
            p.move(to: point(x0, y))
            p.addLine(to: point(x0 + t / 2, y - t / 2))
            p.addLine(to: point(x1 - t / 2, y - t / 2))
            p.addLine(to: point(x1, y))
            p.addLine(to: point(x1 - t / 2, y + t / 2))
            p.addLine(to: point(x0 + t / 2, y + t / 2))
            p.closeSubpath()
            return p
        }
        func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            var p = Path()
            let a = y0 + gap, b = y1 - gap
            p.move(to: point(x, a))
            p.addLine(to: point(x + t / 2, a + t / 2))
            p.addLine(to: point(x + t / 2, b - t / 2))
            p.addLine(to: point(x, b))
            p.addLine(to: point(x - t / 2, b - t / 2))
            p.addLine(to: point(x - t / 2, a + t / 2))
            p.closeSubpath()
            return p
        }

        let left = t / 2, right = w - slant - t / 2
        let top = t / 2, mid = h / 2, bottom = h - t / 2
        return [
            horizontal(top),  // a
            vertical(right, top, mid),  // b
            vertical(right, mid, bottom),  // c
            horizontal(bottom),  // d
            vertical(left, mid, bottom),  // e
            vertical(left, top, mid),  // f
            horizontal(mid),  // g
        ]
    }
}

/// The two dots between hours and minutes.
struct SevenSegmentColon: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let d = geo.size.width
            VStack {
                Spacer()
                Rectangle().fill(color).frame(width: d, height: d)
                Spacer()
                Rectangle().fill(color).frame(width: d, height: d)
                Spacer()
            }
        }
    }
}
