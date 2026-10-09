import SwiftUI

/// Module 593 as the A158W's photo shows it: the same LCD as the F-91W's, but its digits read
/// narrower through the A158W's window. Measured on the A158W photo, in that face's canvas
/// coordinates; `canvasOrigin` is where its glass sits there.
struct A158WDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 368.5, height: 177.5)
    static let canvasOrigin = CGPoint(x: 115, y: 176)

    let context: CasioFaceContext
    let style: LCDStyle

    // Measured on the A158W photo (canvas points).
    static let layout = Module593Layout(
        weekday: LCDRun(glyph: 39, edge: .leading(245.5), baseline: 237.8, xScale: 0.93, tracking: 9.9),
        day: LCDRun(glyph: 44.2, edge: .trailing(474.1), baseline: 242.6, xScale: 0.93, tracking: 4.3, width: 114),
        time: LCDRun(glyph: 85.7, edge: .trailing(385.9), baseline: 345.4, xScale: 0.757, tracking: 8.2, colonGap: 3),
        seconds: LCDRun(glyph: 62.2, edge: .trailing(476.4), baseline: 342.4, xScale: 0.756, tracking: 7),
        pm: CGPoint(x: 152.2, y: 236), pmSize: 27.9, h24: CGPoint(x: 199.75, y: 237.75), h24Size: 18, h24Stretch: 1.12)
    static let runs = layout.runs

    var body: some View {
        inGlass(style: style) { Self.layout.characters(context: context, style: style) }
    }
}
