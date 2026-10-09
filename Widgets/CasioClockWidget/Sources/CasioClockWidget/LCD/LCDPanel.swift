import SwiftUI

/// A watch's LCD as one piece: the window (surround, outline, glass and its light, LCDWindow) with
/// the model's module display placed in the glass, lit when the context says so. The light is
/// applied here for every display, including inverted ones (`LCDStyle.litInk`: the segments glow,
/// the glass stays dark), so a face only says where its window is and which display it shows.
struct LCDPanel<Display: LCDModuleDisplay>: View {
    let display: Display.Type
    /// Outer rectangle of the surround and its outline (canvas points).
    let frame: CGRect
    var frameRadius: CGFloat = 20
    var surround: Color = .black
    var outline: Color = .white
    var outlineWidth: CGFloat = 1.75
    let glass: CGRect
    var glassRadius: CGFloat = 11
    /// Moves the display down within the glass (each case's window frames the module a little
    /// differently; see Module593Display).
    var displayShift: CGFloat = 0
    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let lit = style.lit(context.backlit)
        ZStack(alignment: .topLeading) {
            LCDWindow(
                frame: frame, frameRadius: frameRadius, surround: surround, outline: outline,
                outlineWidth: outlineWidth, glass: glass, glassRadius: glassRadius, backlit: context.backlit,
                style: lit)
            Display.placed(in: glass, shift: displayShift, context: context, style: lit)
        }
    }
}
