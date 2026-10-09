import SwiftUI

/// One character of the live timer text ("10:MM:SS"), shown through a window one digit wide:
/// `charactersAfter` counts the characters to its right (0 = the last seconds digit). The timer
/// text is laid out untracked and right-aligned, so the window's offset is exact; modules whose
/// digits sit closer than DSEG's cells place these windows themselves.
struct TimerDigit: View {
    let start: Date
    let font: LCDFont
    /// Points per em of the font.
    let em: CGFloat
    let charactersAfter: Int

    var body: some View {
        Text(start, style: .timer)
            .contentTransition(.identity)
            .font(font.font(height: em * font.glyphToEm))
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: LiveClock.minutesTimerWidth(em: em), alignment: .trailing)
            .offset(x: Self.hiddenWidth(charactersAfter: charactersAfter, font: font, em: em))
            .frame(width: font.digitAdvance * em, alignment: .trailing)
            .clipped()
    }

    /// Width of the timer text to the right of the character: digits, plus the colon once the
    /// character is left of the seconds ("10:MM:SS").
    static func hiddenWidth(charactersAfter: Int, font: LCDFont, em: CGFloat) -> CGFloat {
        let colons = charactersAfter >= 3 ? 1 : 0
        return (CGFloat(charactersAfter - colons) * font.digitAdvance + CGFloat(colons) * font.colonAdvance) * em
    }
}
