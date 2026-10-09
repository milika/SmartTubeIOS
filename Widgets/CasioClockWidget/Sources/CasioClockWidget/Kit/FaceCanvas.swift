import SwiftUI

/// Draws `content` on a fixed canvas (points measured from a photo of the watch) and scales it
/// to fit the space it is given.
struct FaceCanvas<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack(alignment: .topLeading) { content() }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Placement on the canvas

extension View {
    /// Centers the view at a canvas point.
    func place(centerX: CGFloat, centerY: CGFloat, width: CGFloat? = nil) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: true)
            .position(x: centerX, y: centerY)
    }

    /// Text starting at `leading`, vertically centered on `centerY`.
    func place(leading: CGFloat, centerY: CGFloat, width: CGFloat = 200) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .leading)
            .position(x: leading + width / 2, y: centerY)
    }

    /// Text ending at `trailing`, vertically centered on `centerY`.
    func place(trailing: CGFloat, centerY: CGFloat, width: CGFloat) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .trailing)
            .position(x: trailing - width / 2, y: centerY)
    }

    /// LCD text starting at `leading` with its baseline at `baseline`.
    func place(leading: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .leading)
            .position(x: leading + width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }

    /// LCD text ending at `trailing` with its baseline at `baseline`.
    func place(trailing: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .trailing)
            .position(x: trailing - width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }
}
