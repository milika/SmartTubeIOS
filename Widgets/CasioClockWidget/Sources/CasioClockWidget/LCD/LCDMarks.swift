import SwiftUI

// Fixed LCD marks shared by module displays (A168W, W-738H).

/// The hourly-signal mark: three bars and a sound arc.
struct SignalMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let barWidth = rect.width * 0.14
        for index in 0..<3 {
            path.addRect(
                CGRect(
                    x: rect.minX + CGFloat(index) * rect.width * 0.24, y: rect.minY, width: barWidth,
                    height: rect.height))
        }
        let arc = Path { arc in
            arc.addArc(
                center: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.midY),
                radius: min(rect.width * 0.42, rect.height * 0.6),
                startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
        }
        path.addPath(arc.strokedPath(StrokeStyle(lineWidth: barWidth, lineCap: .butt)))
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
