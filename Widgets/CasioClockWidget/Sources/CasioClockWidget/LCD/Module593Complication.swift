import SwiftUI
import WidgetKit

/// Module 593's display as a rectangular Apple Watch complication, on a 200×80 canvas: PM / weekday
/// / date on top, H:MM and live seconds below. A compact layout of its own (the slot is wider and
/// shorter than the watch's glass, so Module593Display doesn't fit it); any model with module 593
/// can offer it. Full-colour faces get the model's glass and ink; tinted faces get white ink in
/// the face's tint (no glass).
struct Module593Complication: View {
    static let canvas = CGSize(width: 200, height: 80)

    let context: CasioFaceContext
    /// The model's LCD style (full colour).
    let lcd: LCDStyle
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fullColor: Bool { renderingMode == .fullColor }

    private var style: LCDStyle {
        var lcdStyle = lcd
        if !fullColor {
            lcdStyle.ink = .white
        }
        return lcdStyle
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
                    xScale: Module593Display.digitSqueeze, style: style)
                LiveSeconds(
                    context: context, glyph: 32, trailing: 196, baseline: 75, xScale: Module593Display.digitSqueeze,
                    style: style)
            }
            .widgetAccentable()
        }
    }
}
