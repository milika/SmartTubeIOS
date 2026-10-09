import SwiftUI

// How the time stays live with one timeline entry per hour:
// - The hours (and date, weekday, PM / 24H) come from the entry, which changes on the hour.
// - Minutes and seconds come from one WidgetKit timer text ("H:MM:SS") that animates itself, cut to
//   the two digits needed. Before, each minute was its own timeline entry; for detailed faces an
//   hour of fully drawn entries grew too large for WidgetKit (36 MB, rejected), and one timer keeps
//   minutes and seconds in step.

enum LiveClock {
    /// The timer's start: 10 hours before the current hour, so it always reads "10:MM:SS" (two-digit
    /// hours, zero-padded minutes and seconds) and the minutes are the two digits before the last colon.
    static func timerStart(for date: Date, calendar: Calendar) -> Date {
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return hourStart.addingTimeInterval(-10 * 3600)
    }
}

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
    let style: LCDStyle

    var body: some View {
        let parts = DisplayParts.make(
            for: context.date, calendar: context.calendar, twelveHour: context.uses12HourClock,
            blankDigit: font.blankDigit)
        let em = glyph / font.glyphToEm
        let minutesWidth = 2 * font.digitAdvance * em
        // ":SS" to the right of the minutes in the timer text.
        let hiddenWidth = (font.colonAdvance + 2 * font.digitAdvance) * em
        let width = (4 * font.digitAdvance + font.colonAdvance) * em
        let hours = String(parts.hoursMinutes.prefix(while: { $0 != ":" })) + ":"
        let minutes: AnyView =
            if context.previewSeconds != nil {
                AnyView(Text(String(parts.hoursMinutes.suffix(2))).font(font.font(height: glyph)).lineLimit(1))
            } else {
                AnyView(
                    Text(LiveClock.timerStart(for: context.date, calendar: context.calendar), style: .timer)
                        .font(font.font(height: glyph))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(width: 8 * em, alignment: .trailing)
                        .offset(x: hiddenWidth)
                        .frame(width: minutesWidth, alignment: .trailing)
                        .clipped())
            }
        ZStack(alignment: .trailing) {
            if style.unlitOpacity > 0, let lit = font.allLit("88:88") {
                Text(lit).font(font.font(height: glyph)).foregroundStyle(style.ink.opacity(style.unlitOpacity))
            }
            Text(hours).font(font.font(height: glyph)).lineLimit(1)
                .padding(.trailing, minutesWidth)
            minutes
        }
        .foregroundStyle(style.ink)
        .frame(width: width, alignment: .trailing)
        .scaleEffect(x: xScale, y: 1, anchor: .trailing)
        .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
    }
}
