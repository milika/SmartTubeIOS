import SwiftUI

/// Live seconds: the shared timer text ("10:MM:SS", see LiveClock), shown through a right-aligned
/// window that keeps only the last two digits. Widgets can't redraw every second, but timer text
/// animates itself.
struct LiveSeconds: View {
    /// The entry's time; `context.previewSeconds` fixes the seconds for static renders (the
    /// timer only animates inside a widget).
    let context: CasioFaceContext
    let glyph: CGFloat
    let trailing: CGFloat
    let baseline: CGFloat
    var xScale: CGFloat = 1
    let style: LCDStyle

    var body: some View {
        let start = LiveClock.timerStart(for: context.date, calendar: context.calendar)
        let font = style.digits
        let digitAdvance = glyph / font.glyphToEm * font.digitAdvance
        let window = digitAdvance * 2.02
        let live: Text = context.previewSeconds.map { Text(String(format: "%02d", $0)) } ?? Text(start, style: .timer)
        ZStack(alignment: .topLeading) {
            if style.unlitOpacity > 0, let lit = font.allLit("00") {
                Text(lit).font(font.font(height: glyph))
                    .foregroundStyle(style.ink.opacity(style.unlitOpacity))
                    .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                    .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
            }
            live
                // No rolling digits: the window shows a slice of the timer (LiveClock).
                .contentTransition(.identity)
                .font(font.font(height: glyph))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                // Room for the whole "10:MM:SS" so it isn't truncated (LiveClock); the window keeps the
                // last two digits.
                .frame(width: LiveClock.secondsTimerWidth(digitAdvance: digitAdvance), alignment: .trailing)
                .frame(width: window, alignment: .trailing)
                .clipped()
                .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
        }
    }
}
