import SwiftUI

// Fixed LCD marks shared by module displays.

/// The hourly time signal mark: a filled "D" followed by `arcs` arcs of the same curvature, as
/// Casio's LCDs show it. The rect is the mark's ink box.
struct SignalMark: Shape {
    var arcs = 4

    func path(in rect: CGRect) -> Path {
        // In units of one arc's thickness: the D is 1.6 units wide, each arc 1 after a 0.6 gap,
        // and every right edge bulges 0.8.
        let unit = rect.width / (1.6 + 1.6 * CGFloat(arcs) + 0.8)
        let bulge = 0.8 * unit
        let top = rect.minY, bottom = rect.maxY, mid = rect.midY
        var path = Path()
        // The D: straight left edge, curved right edge.
        let dRight = rect.minX + 1.6 * unit
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: dRight, y: top))
        path.addQuadCurve(to: CGPoint(x: dRight, y: bottom), control: CGPoint(x: dRight + 2 * bulge, y: mid))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom))
        path.closeSubpath()
        // The arcs: a crescent between two curves bulging right.
        for index in 0..<arcs {
            let left = dRight + 0.6 * unit + CGFloat(index) * 1.6 * unit
            path.move(to: CGPoint(x: left, y: top))
            path.addQuadCurve(to: CGPoint(x: left, y: bottom), control: CGPoint(x: left + 2 * bulge, y: mid))
            path.addLine(to: CGPoint(x: left + unit, y: bottom))
            path.addQuadCurve(to: CGPoint(x: left + unit, y: top), control: CGPoint(x: left + unit + 2 * bulge, y: mid))
            path.closeSubpath()
        }
        return path
    }
}

/// The alarm mark: a bell with its clapper.
struct BellMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width, height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + width * x, y: rect.minY + height * y)
        }
        path.move(to: point(0.5, 0))
        path.addCurve(to: point(0.12, 0.78), control1: point(0.15, 0), control2: point(0.2, 0.55))
        path.addLine(to: point(0, 0.86))
        path.addLine(to: point(1, 0.86))
        path.addLine(to: point(0.88, 0.78))
        path.addCurve(to: point(0.5, 0), control1: point(0.8, 0.55), control2: point(0.85, 0))
        path.closeSubpath()
        path.addEllipse(
            in: CGRect(
                x: rect.midX - width * 0.15, y: rect.minY + height * 0.86, width: width * 0.3, height: height * 0.14))
        return path
    }
}
