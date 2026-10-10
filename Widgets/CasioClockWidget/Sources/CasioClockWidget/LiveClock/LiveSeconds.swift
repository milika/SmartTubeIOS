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
    /// Extra space after each digit, in points before `xScale` (see LiveHoursMinutes); each live
    /// digit then gets its own TimerDigit window.
    var tracking: CGFloat = 0
    let style: LCDStyle

    var body: some View {
        Group {
            if tracking == 0 { packedLayout } else { trackedLayout }
        }
        // New timer views for each light state: timer text keeps its old ink until its next tick,
        // so on inverted displays the live digits lit up after the rest.
        .id(context.backlit)
        .transition(.identity)
    }

    private var trackedLayout: some View {
        let start = LiveClock.timerStart(for: context.date, calendar: context.calendar)
        let font = style.digits
        let em = glyph / font.glyphToEm
        let cell = font.digitAdvance * em + tracking
        let width = 2 * cell
        let fixed = context.previewSeconds.map { String(format: "%02d", $0) }.map(Array.init)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                Group {
                    if let fixed {
                        Text(String(fixed[index])).font(font.font(height: glyph)).lineLimit(1).fixedSize()
                    } else {
                        // Seconds in "10:MM:SS": tens 2nd from the end, units last.
                        TimerDigit(start: start, font: font, em: em, charactersAfter: index == 0 ? 1 : 0)
                    }
                }
                .offset(x: CGFloat(index) * cell)
            }
        }
        .foregroundStyle(style.ink)
        .frame(width: width, alignment: .topLeading)
        .scaleEffect(x: xScale, y: 1, anchor: .trailing)
        .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
    }

    @ViewBuilder private var packedLayout: some View {
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
