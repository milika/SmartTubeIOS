import SwiftUI

/// A rectangle with its four corners cut off diagonally (`cut` across and down) and the joints
/// rounded, like the frame lines printed on the F-91W.
struct CutCornerRect: Shape {
    let cut: CGSize
    /// The bottom corners' cut, if different from the top ones.
    var bottomCut: CGSize? = nil
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = CGSize(width: min(cut.width, rect.width / 2), height: min(cut.height, rect.height / 2))
        let b = bottomCut ?? cut
        let bottom = CGSize(width: min(b.width, rect.width / 2), height: min(b.height, rect.height / 2))
        let corners = [
            CGPoint(x: rect.minX + top.width, y: rect.minY), CGPoint(x: rect.maxX - top.width, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + top.height), CGPoint(x: rect.maxX, y: rect.maxY - bottom.height),
            CGPoint(x: rect.maxX - bottom.width, y: rect.maxY), CGPoint(x: rect.minX + bottom.width, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - bottom.height), CGPoint(x: rect.minX, y: rect.minY + top.height),
        ]
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        for i in 1...corners.count {
            p.addArc(tangent1End: corners[i % corners.count], tangent2End: corners[(i + 1) % corners.count], radius: radius)
        }
        p.closeSubpath()
        return p
    }
}

/// The small red triangles beside LIGHT, MODE and 24HR.
struct Pointer: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if left {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
