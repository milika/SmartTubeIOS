import SwiftUI

/// Live seconds: the shared timer text ("10:MM:SS", see LiveClock), shown through a right-aligned
/// window that keeps only the last two digits. Widgets can't redraw every second, but timer text
/// animates itself.
struct LiveSeconds: View {
    let date: Date
    let calendar: Calendar
    /// Fixed seconds for static renders (the timer only animates inside a widget).
    let previewSeconds: Int?
    let glyph: CGFloat
    let trailing: CGFloat
    let baseline: CGFloat
    var xScale: CGFloat = 1
    let style: LCDStyle

    var body: some View {
        let start = LiveClock.timerStart(for: date, calendar: calendar)
        let font = style.digits
        let digitAdvance = glyph / font.glyphToEm * font.digitAdvance
        let window = digitAdvance * 2.02
        let live: Text = previewSeconds.map { Text(String(format: "%02d", $0)) } ?? Text(start, style: .timer)
        ZStack(alignment: .topLeading) {
            if style.unlitOpacity > 0, let lit = font.allLit("00") {
                Text(lit).font(font.font(height: glyph))
                    .foregroundStyle(style.ink.opacity(style.unlitOpacity))
                    .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                    .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
            }
            live
                .font(font.font(height: glyph))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                // Room for the whole "10:MM:SS" so it isn't truncated; the window keeps the last two digits.
                .frame(width: digitAdvance * 10, alignment: .trailing)
                .frame(width: window, alignment: .trailing)
                .clipped()
                .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
        }
    }
}
