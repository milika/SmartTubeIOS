import SwiftUI

/// The display of one Casio LCD module: what its characters show and where, for a face context.
/// Casio puts one module into several watches (593: F-91W, A158W, A168W; 3459: GMW-B5000 and its
/// 5600-series sisters), so a display is measured once, in the glass of one reference photo, and
/// each watch model places it in its own glass (`placed(in:)`); the face only draws the case.
protocol LCDModuleDisplay: View {
    /// Size of the glass the layout was measured in.
    static var glass: CGSize { get }
    init(context: CasioFaceContext, style: LCDStyle)
}

extension LCDModuleDisplay {
    /// The display in a model's glass (canvas coordinates): scaled to the glass's width and centred
    /// vertically, so a taller glass (a case extended to fill the widget) gets even margins.
    /// `shift` moves it down: each case's window frames the same LCD at a slightly different spot.
    static func placed(
        in glass: CGRect, shift: CGFloat = 0, context: CasioFaceContext, style: LCDStyle
    )
        -> some View
    {
        let scale = glass.width / Self.glass.width
        return Self(context: context, style: style)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: glass.minX, y: glass.minY + (glass.height - Self.glass.height * scale) / 2 + shift)
    }
}
