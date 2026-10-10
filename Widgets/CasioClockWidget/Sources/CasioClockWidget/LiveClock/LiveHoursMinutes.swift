import SwiftUI

/// "H:MM" in LCD digits: the hours from the timeline entry, the minutes live from the timer (cut
/// out of "10:MM:SS"). Placed like `LCDText` with a trailing edge; `previewSeconds` (static renders)
/// draws the minutes as plain text.
struct LiveHoursMinutes: View {
    let context: CasioFaceContext
    let font: LCDFont
    let glyph: CGFloat
    let trailing: CGFloat
    let baseline: CGFloat
    var xScale: CGFloat = 1
    /// Extra space around the colon, in points before `xScale` (some modules space it wider than DSEG).
    var colonGap: CGFloat = 0
    /// Extra space after each character, in points before `xScale`; negative packs the digits
    /// tighter than DSEG's cells, as on some modules. The timer text itself is never tracked: each
    /// live digit gets its own window (TimerDigit), so the clipping stays exact.
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

    /// Each character in its own cell, `tracking` apart: hours and colon as text, minutes as two
    /// TimerDigit windows (or plain digits in static renders).
    private var trackedLayout: some View {
        let parts = context.displayParts(blankDigit: font.blankDigit)
        let em = glyph / font.glyphToEm
        let cell = font.digitAdvance * em + tracking
        let colonCell = font.colonAdvance * em + tracking
        let width = 4 * cell + colonCell + colonGap
        let hours = Array(parts.hoursMinutes.prefix(while: { $0 != ":" }))
        let minutes = Array(parts.hoursMinutes.suffix(2))
        let start = LiveClock.timerStart(for: context.date, calendar: context.calendar)
        let digitFont = font.font(height: glyph)
        // Leading x of each cell, left to right: H H : M M.
        let colonX = 2 * cell + colonGap / 2
        let minutesX = 2 * cell + colonCell + colonGap
        return ZStack(alignment: .topLeading) {
            ForEach(0..<hours.count, id: \.self) { index in
                Text(String(hours[index])).font(digitFont).lineLimit(1).fixedSize()
                    .offset(x: CGFloat(2 - hours.count + index) * cell)
            }
            Text(":").font(digitFont).lineLimit(1).fixedSize().offset(x: colonX)
            ForEach(0..<2, id: \.self) { index in
                Group {
                    if context.previewSeconds != nil {
                        Text(String(minutes[index])).font(digitFont).lineLimit(1).fixedSize()
                    } else {
                        // Minutes in "10:MM:SS": tens 4th from the end, units 3rd (after the colon).
                        TimerDigit(start: start, font: font, em: em, charactersAfter: index == 0 ? 4 : 3)
                    }
                }
                .offset(x: minutesX + CGFloat(index) * cell)
            }
        }
        .foregroundStyle(style.ink)
        .frame(width: width, alignment: .topLeading)
        .scaleEffect(x: xScale, y: 1, anchor: .trailing)
        .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
    }

    @ViewBuilder private var packedLayout: some View {
        let parts = context.displayParts(blankDigit: font.blankDigit)
        let em = glyph / font.glyphToEm
        let minutesWidth = 2 * font.digitAdvance * em
        // ":SS" to the right of the minutes in the timer text.
        let hiddenWidth = (font.colonAdvance + 2 * font.digitAdvance) * em
        let width = (4 * font.digitAdvance + font.colonAdvance) * em + colonGap
        let hours = String(parts.hoursMinutes.prefix(while: { $0 != ":" }))
        let minutes: AnyView =
            if context.previewSeconds != nil {
                AnyView(Text(String(parts.hoursMinutes.suffix(2))).font(font.font(height: glyph)).lineLimit(1))
            } else {
                AnyView(
                    Text(LiveClock.timerStart(for: context.date, calendar: context.calendar), style: .timer)
                        // No rolling digits: the window shows a slice of the timer (LiveClock).
                        .contentTransition(.identity)
                        .font(font.font(height: glyph))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(width: LiveClock.minutesTimerWidth(em: em), alignment: .trailing)
                        .offset(x: hiddenWidth)
                        .frame(width: minutesWidth, alignment: .trailing)
                        .clipped())
            }
        ZStack(alignment: .trailing) {
            if style.unlitOpacity > 0, let lit = font.allLit("88:88") {
                Text(lit).font(font.font(height: glyph)).foregroundStyle(style.ink.opacity(style.unlitOpacity))
            }
            if colonGap == 0 {
                Text(hours + ":").font(font.font(height: glyph)).lineLimit(1)
                    .padding(.trailing, minutesWidth)
            } else {
                Text(hours).font(font.font(height: glyph)).lineLimit(1)
                    .padding(.trailing, minutesWidth + font.colonAdvance * em + colonGap)
                Text(":").font(font.font(height: glyph)).lineLimit(1)
                    .padding(.trailing, minutesWidth + colonGap / 2)
            }
            minutes
        }
        .foregroundStyle(style.ink)
        .frame(width: width, alignment: .trailing)
        .scaleEffect(x: xScale, y: 1, anchor: .trailing)
        .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
    }
}
