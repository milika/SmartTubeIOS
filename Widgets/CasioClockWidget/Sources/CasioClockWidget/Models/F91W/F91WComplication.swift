import SwiftUI
import WidgetKit

/// The F-91W's LCD as a rectangular complication, on a 200×80 canvas: PM / weekday / date on
/// top, H:MM and live seconds below. Full-colour faces get the grey-green glass and dark ink;
/// tinted faces get white ink in the face's tint (no glass).
struct F91WComplication: View {
    static let canvas = CGSize(width: 200, height: 80)

    let context: CasioFaceContext
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fullColor: Bool { renderingMode == .fullColor }

    private var style: LCDStyle {
        var s = CasioF91W.lcd
        if !fullColor {
            s.ink = .white
        }
        return s
    }

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        FaceCanvas(size: Self.canvas) {
            if fullColor {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.glass)
                    .frame(width: Self.canvas.width, height: Self.canvas.height)
            }
            Group {
                if let marker = parts.marker {
                    Text(marker)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(style.ink)
                        .place(leading: 8, centerY: 14, width: 40)
                }
                LCDText(
                    text: parts.weekday, font: style.letters, glyph: 17, edge: .leading(62), baseline: 22,
                    tracking: 3, style: style)
                LCDText(
                    text: parts.day, font: style.digits, glyph: 19, edge: .trailing(194), baseline: 23, width: 60,
                    tracking: 2, style: style)
                LiveHoursMinutes(
                    context: context, font: style.digits, glyph: 44, trailing: 148, baseline: 75,
                    xScale: CasioF91W.digitSqueeze, style: style)
                LiveSeconds(
                    context: context, glyph: 32, trailing: 196, baseline: 75, xScale: CasioF91W.digitSqueeze,
                    style: style)
            }
            .widgetAccentable()
        }
    }
}
