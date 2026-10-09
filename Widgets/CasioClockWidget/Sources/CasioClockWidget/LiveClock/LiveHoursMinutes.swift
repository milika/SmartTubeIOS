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
    let style: LCDStyle

    var body: some View {
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
