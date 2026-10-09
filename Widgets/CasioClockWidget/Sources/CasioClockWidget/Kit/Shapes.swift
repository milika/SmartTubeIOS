import SwiftUI

/// A rectangle with its four corners cut off diagonally (`cut` across and down) and the joints
/// rounded, like the frame lines printed on the F-91W.
struct CutCornerRect: Shape {
    let cut: CGSize
    /// The bottom corners' cut, if different from the top ones.
    var bottomCut: CGSize?
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = CGSize(width: min(cut.width, rect.width / 2), height: min(cut.height, rect.height / 2))
        let bottomCutSize = bottomCut ?? cut
        let bottom = CGSize(
            width: min(bottomCutSize.width, rect.width / 2), height: min(bottomCutSize.height, rect.height / 2))
        let corners = [
            CGPoint(x: rect.minX + top.width, y: rect.minY), CGPoint(x: rect.maxX - top.width, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + top.height), CGPoint(x: rect.maxX, y: rect.maxY - bottom.height),
            CGPoint(x: rect.maxX - bottom.width, y: rect.maxY), CGPoint(x: rect.minX + bottom.width, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - bottom.height), CGPoint(x: rect.minX, y: rect.minY + top.height),
        ]
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        for index in 1...corners.count {
            path.addArc(
                tangent1End: corners[index % corners.count], tangent2End: corners[(index + 1) % corners.count],
                radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// A small triangle pointing left or right, like the ones beside the button labels.
struct Pointer: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if left {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// Staggered bricks (each row offset by half a brick), like the G-Shock 5000 faces.
struct BrickPattern: Shape {
    let brick: CGSize
    let pitch: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var row = 0
        var y = rect.minY + (pitch.height - brick.height) / 2
        while y < rect.maxY {
            var x = rect.minX - (row % 2 == 0 ? 0 : pitch.width / 2)
            while x < rect.maxX {
                path.addRect(CGRect(x: x, y: y, width: brick.width, height: brick.height))
                x += pitch.width
            }
            y += pitch.height
            row += 1
        }
        return path
    }
}

/// The G-Shock SHOCK RESIST shield: the top corners cut by `cornerPoints` plus `cornerFraction`
/// of the width, straight sides down to `shoulder` (a fraction of the height), then a point at the
/// bottom centre. Each watch prints it in its own proportions.
struct ShockResistShield: Shape {
    var cornerPoints: CGFloat = 0
    var cornerFraction: CGFloat = 0
    let shoulder: CGFloat

    func path(in rect: CGRect) -> Path {
        let corner = cornerPoints + rect.width * cornerFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * shoulder))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * shoulder))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.closeSubpath()
        return path
    }
}
