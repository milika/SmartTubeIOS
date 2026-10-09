import SwiftUI

/// How a model's LCD looks: segment fonts, glass, ink, optional faint unlit segments and
/// backlight. The defaults are the F-91W's (DSEG Bold Italic on grey-green glass; no unlit
/// segments: on the real watch they're invisible straight on).
struct LCDStyle {
    var digits: LCDFont = .dseg7("BoldItalic")
    var letters: LCDFont = .dseg14("BoldItalic")
    /// Opacity of the unlit segments behind the characters; 0 = off.
    var unlitOpacity: Double = 0
    var glass: Color = Color(red: 0.67, green: 0.74, blue: 0.68)
    var ink: Color = Color(red: 0.11, green: 0.16, blue: 0.19)
    var backlight: Color = Color(red: 0.42, green: 0.91, blue: 0.67)
    /// Backlight opacity from the leading to the trailing edge (one LED at the left: fades right).
    var backlightFalloff: [Double] = [1, 0.8, 0.55]
    /// Depth: the frame's shadow on the glass and the segments' shadow on the reflector.
    var shadow = LCDShadow()
}

/// The LCD's shadows, the same for every model (in canvas points, light from the top left):
/// the glass sits below its frame, which shades its top and left edge, and the segments cast a
/// faint shadow on the reflector behind them, offset down and right.
struct LCDShadow {
    /// Opacity of the frame's shadow at the glass edge; 0 = none.
    var edgeOpacity: Double = 0.45
    /// How far the edge shadow reaches into the glass.
    var edgeWidth: CGFloat = 9
    /// Opacity of the segments' shadow (in the ink colour); 0 = none.
    var segmentOpacity: Double = 0.22
    var segmentOffset = CGSize(width: 2.5, height: 3)
    var segmentBlur: CGFloat = 1
}

extension View {
    /// The segments' shadow on the reflector (see LCDShadow); apply to a model's LCD characters.
    func lcdSegmentShadow(_ style: LCDStyle) -> some View {
        shadow(
            color: style.ink.opacity(style.shadow.segmentOpacity), radius: style.shadow.segmentBlur,
            x: style.shadow.segmentOffset.width, y: style.shadow.segmentOffset.height)
    }
}
