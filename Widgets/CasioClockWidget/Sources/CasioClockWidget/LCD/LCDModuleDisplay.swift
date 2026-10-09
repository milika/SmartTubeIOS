import SwiftUI

/// The display of one Casio LCD module: what its characters show and where, for a face context.
/// Casio puts one module into several watches (593: F-91W, A158W, A168W; 3459: GMW-B5000 and its
/// 5600-series sisters), so a display is measured once, in the glass of one reference photo, and
/// each watch model places it in its own glass (`placed(in:)`); the face only draws the case.
protocol LCDModuleDisplay: View {
    /// Size of the glass the layout was measured in.
    static var glass: CGSize { get }
    /// Where that glass's top-left corner sits on the canvas the layout's numbers were measured on
    /// (the reference face's canvas); .zero when measured in the glass itself.
    static var canvasOrigin: CGPoint { get }
    /// The display's measured lines of characters (weekday, date, time, seconds, …).
    static var runs: [LCDRun] { get }
    init(context: CasioFaceContext, style: LCDStyle)
}

extension LCDModuleDisplay {
    static var canvasOrigin: CGPoint { .zero }

    /// The display's characters, laid out in the measured canvas coordinates, shown in its glass
    /// with the segments' shadow. Each display's `body` is `inGlass(style:) { … }`.
    func inGlass<Content: View>(style: LCDStyle, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) { content() }
            .lcdSegmentShadow(style)
            .offset(x: -Self.canvasOrigin.x, y: -Self.canvasOrigin.y)
            .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    /// The display in a model's glass (canvas coordinates): scaled to the glass's width and centred
    /// vertically, so a taller glass (a case extended to fill the widget) gets even margins.
    static func placed(
        in glass: CGRect, context: CasioFaceContext, style: LCDStyle
    )
        -> some View
    {
        let scale = glass.width / Self.glass.width
        return Self(context: context, style: style)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: glass.minX, y: glass.minY + (glass.height - Self.glass.height * scale) / 2)
    }
}
