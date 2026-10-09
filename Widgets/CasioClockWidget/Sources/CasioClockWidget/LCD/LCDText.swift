import SwiftUI

/// LCD characters with their unlit segments faintly behind them, placed by baseline.
struct LCDText: View {
    enum Edge { case leading(CGFloat), trailing(CGFloat) }

    let text: String
    let font: LCDFont
    let glyph: CGFloat
    let edge: Edge
    let baseline: CGFloat
    var width: CGFloat = 200
    var tracking: CGFloat = 0
    /// Horizontal squeeze (1 = DSEG's own width).
    var xScale: CGFloat = 1
    let style: LCDStyle

    var body: some View {
        let layers: [(String, Double)] =
            [(font.allLit(text), style.unlitOpacity), (text, 1)].compactMap { item in
                guard let layerText = item.0, item.1 > 0 else { return nil }
                return (layerText, item.1)
            }
        ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
            let view = Text(layer.0).font(font.font(height: glyph)).tracking(tracking)
                .foregroundStyle(style.ink.opacity(layer.1))
            switch edge {
            case .leading(let x):
                view.scaleEffect(x: xScale, y: 1, anchor: .leading)
                    .place(leading: x, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            case .trailing(let x):
                view.scaleEffect(x: xScale, y: 1, anchor: .trailing)
                    .place(trailing: x, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            }
        }
    }
}
