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
}
