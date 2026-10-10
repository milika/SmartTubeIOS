import SwiftUI

/// The ABL-100WE's display (named after the watch; its module number is not checked here): a step
/// bar from 0 to 100 above a rule; MUTE, the weekday in 5×5 dot letters, the year as 'YY- and
/// the month-date; under a second rule P, a large H:MM, the signal and alarm marks and the seconds.
/// Upright 7-segment digits. Measured on a front-on product image of the ABL-100WE-1A, in that
/// face's canvas coordinates; `canvasOrigin` is where its 311.5 × 208 glass sits on that canvas
/// (`placed(in:)`). The step bar shows today's steps from the Health app toward 10,000 (CasioSteps):
/// one bar per 1/17 of the goal, none when the steps aren't known. MUTE and the marks are shown as
/// in the image.
struct ABL100WEDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 311.5, height: 208)
    /// The glass's top-left corner on the ABL-100WE canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 156, y: 244)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.year, .month, .day], from: context.date)
        let blank = style.digits.blankDigit
        inGlass(style: style) {
            stepBar
            Rectangle().fill(style.ink).frame(width: 311.5, height: 1.5).offset(x: 156, y: 269.5)
            label("MUTE", CGRect(x: 322.5, y: 276.5, width: 51, height: 10.5))
            if let diagnostic = Self.diagnostic(context) {
                // Lit (tapped): where the steps came from and the count, instead of the date.
                weekdayLetters(diagnostic.source)
                LCDText(text: diagnostic.steps, font: style.digits, run: Self.stepCount, style: style)
            } else {
                weekdayLetters(DisplayParts.weekday3(for: context.date, calendar: context.calendar))
                // 'YY- then M-DD.
                Rectangle().fill(style.ink).frame(width: 3, height: 6).offset(x: 284.5, y: 294.5)
                LCDText(
                    text: String(format: "%02d", (date.year ?? 2000) % 100), font: style.digits, run: Self.year,
                    style: style)
                Rectangle().fill(style.ink).frame(width: 9.5, height: 4).offset(x: 339.5, y: 309.5)
                LCDText(
                    text: DisplayParts.twoCells(date.month ?? 1, blank: blank), font: style.digits, run: Self.month,
                    style: style)
                Rectangle().fill(style.ink).frame(width: 9.5, height: 4).offset(x: 401.5, y: 309.5)
                LCDText(
                    text: DisplayParts.twoCells(date.day ?? 1, blank: blank), font: style.digits, run: Self.day,
                    style: style)
            }
            Rectangle().fill(style.ink).frame(width: 311.5, height: 3).offset(x: 156, y: 341)
            if parts.isPM {
                InkText(text: "P", font: CaseFont.saira)
                    .placed(in: CGRect(x: 171.5, y: 374, width: 10, height: 10.5), color: style.ink, bold: 0.6)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            SignalMark(arcs: 3).fill(style.ink).frame(width: 28, height: 11).offset(x: 404.5, y: 374.5)
            BellMark().fill(style.ink).frame(width: 17, height: 18.5).offset(x: 435.5, y: 369.5)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    /// The step diagnostic shown while the widget is lit: the source code (HEA, APP, WID, NON;
    /// CasioSteps.Source) and the count ("0" when unknown). Nil when not lit or the timeline had
    /// no step reading (previews, reference renders).
    static func diagnostic(_ context: CasioFaceContext) -> (source: String, steps: String)? {
        guard context.backlit, let source = context.stepSource else { return nil }
        return (source, String(context.steps ?? 0))
    }

    private func weekdayLetters(_ text: String) -> some View {
        DotMatrixText(
            text: text, pitch: CGSize(width: 6.05, height: 6.85), dot: CGSize(width: 4.75, height: 5.5),
            advance: 36.3, narrowAdvance: 18, color: style.ink, glyphs: .block5x5, slant: 0.055
        )
        .frame(width: 120, height: 36, alignment: .topLeading)
        .offset(x: 166, y: 295.5)
    }

    /// The bar's segments.
    static let stepSegments = 17

    /// Segments lit for a step count: one per full 1/17 of the goal.
    static func litSegments(steps: Int?) -> Int {
        Int((CasioSteps.progress(steps) * Double(stepSegments)).rounded(.down))
    }

    /// "0", the lit bars and "100".
    private var stepBar: some View {
        ZStack(alignment: .topLeading) {
            label("0", CGRect(x: 204, y: 248, width: 8, height: 9.5))
            ForEach(0..<Self.litSegments(steps: context.steps), id: \.self) { index in
                Rectangle().fill(style.ink).frame(width: 7.25, height: 15)
                    .offset(x: 217.5 + 9.5 * CGFloat(index), y: 245.5)
            }
            label("100", CGRect(x: 413.5, y: 248.5, width: 22.5, height: 11))
        }
    }

    private func label(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.6, barBold: 0.4)
    }

    // Measured on the ABL-100WE image (canvas points).
    static let year = LCDRun(glyph: 34.5, edge: .trailing(336.9), baseline: 329, xScale: 0.974, tracking: -1.46)
    static let month = LCDRun(glyph: 34.5, edge: .trailing(398.9), baseline: 329, xScale: 0.93, tracking: -1.9)
    static let day = LCDRun(glyph: 34.5, edge: .trailing(460.4), baseline: 329, xScale: 0.93, tracking: -1.9)
    static let time = LCDRun(
        glyph: 64.5, edge: .trailing(379.9), baseline: 436.5, xScale: 0.966, tracking: -1.9, colonGap: 0.4)
    static let seconds = LCDRun(glyph: 41.5, edge: .trailing(457.7), baseline: 436.5, xScale: 0.968, tracking: 3.3)
    /// The lit step count: the date row's digits, right-aligned at the day's edge.
    static let stepCount = LCDRun(glyph: 34.5, edge: .trailing(460.4), baseline: 329, xScale: 0.93, tracking: -1.9)
    static let runs = [year, month, day, time, seconds, stepCount]
}
