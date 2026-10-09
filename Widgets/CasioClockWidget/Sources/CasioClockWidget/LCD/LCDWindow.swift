import SwiftUI

/// The LCD's framed dark surround and its glass, lit by the backlight when `backlit`.
struct LCDWindow: View {
    /// Outer rectangle of the dark surround and its outline.
    let frame: CGRect
    var frameRadius: CGFloat = 20
    var outline: Color = .white
    var outlineWidth: CGFloat = 1.75
    let glass: CGRect
    var glassRadius: CGFloat = 11
    let backlit: Bool
    let style: LCDStyle

    var body: some View {
        RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
            .fill(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
                    .strokeBorder(outline, lineWidth: outlineWidth)
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
            .fill(LinearGradient(colors: [style.glass, style.glass.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if backlit {
                    RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: style.backlightFalloff.map { style.backlight.opacity($0) },
                                startPoint: .leading, endPoint: .trailing))
                }
            }
            .frame(width: glass.width, height: glass.height)
            .offset(x: glass.minX, y: glass.minY)
    }
}
