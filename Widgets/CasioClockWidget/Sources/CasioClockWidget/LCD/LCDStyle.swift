import SwiftUI

/// How a model's LCD looks: segment fonts, glass, ink, faint unlit segments and backlight.
/// The defaults are the F-91W's (chosen from prototypes: DSEG Bold Italic with faint unlit
/// segments on grey-green glass).
struct LCDStyle {
    var digits: LCDFont = .dseg7("BoldItalic")
    var letters: LCDFont = .dseg14("BoldItalic")
    /// Opacity of the unlit segments behind the characters; 0 = off.
    var unlitOpacity: Double = 0.055
    var glass: Color = Color(red: 0.67, green: 0.74, blue: 0.68)
    var ink: Color = Color(red: 0.11, green: 0.16, blue: 0.19)
    var backlight: Color = Color(red: 0.36, green: 0.86, blue: 0.62)
    /// Backlight opacity from the leading to the trailing edge (one LED at the left: fades right).
    var backlightFalloff: [Double] = [1, 0.75, 0.45]
}
