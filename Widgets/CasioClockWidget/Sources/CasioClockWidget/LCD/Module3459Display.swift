import SwiftUI

/// The display of Casio's module 3459 (GMW-B5000; the GW-B5600 family shows the same layout):
/// PS / RCVD / DST / P indicators, weekday, a boxed dot-matrix date, H:MM and live seconds.
/// Measured on the GMW-B5000 photo, in that face's canvas coordinates; `canvasOrigin` is where its
/// 313 × 207 glass sits on that canvas, so the layout lands in any model's glass (`placed(in:)`).
struct Module3459Display: LCDModuleDisplay {
    static let glass = CGSize(width: 313, height: 207)
    /// The glass's top-left corner on the GMW-B5000 canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 151, y: 176)

    let context: CasioFaceContext
    let style: LCDStyle

    // Measured character runs (canvas points).
    static let weekday = LCDRun(glyph: 41.5, edge: .leading(227), baseline: 251.5, tracking: 2)
    static let time = LCDRun(glyph: 76, edge: .trailing(372), baseline: 362.5, xScale: 0.85, colonGap: -5)
    static let seconds = LCDRun(glyph: 50, edge: .trailing(450), baseline: 360.5, xScale: 0.93)
    static let runs = [weekday, time, seconds]

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        inGlass(style: style) {
            indicator("PS", leading: 178, centerY: 197.75, tracking: 5.3)
            indicator("RCVD", leading: 250, centerY: 198.25)
            if context.calendar.timeZone.isDaylightSavingTime(for: context.date) {
                indicator("DST", leading: 197, centerY: 270.75, tracking: 3.1)
            }
            // P for PM on a 12-hour clock (the G-Shock shows nothing on a 24-hour clock).
            if parts.isPM {
                indicator("P", leading: 161, centerY: 304)
            }
            LCDText(text: parts.weekday, font: style.letters, run: Self.weekday, style: style)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(style.ink, lineWidth: 1.6)
                .frame(width: 136, height: 61)
                .offset(x: 311, y: 201)
            DotMatrixText(
                text: Self.dateText(context.date, calendar: context.calendar, dayFirst: Self.localeDayFirst),
                pitch: CGSize(width: 4, height: 5.7), dot: CGSize(width: 3.3, height: 4.8), advance: 27.25,
                narrowAdvance: 14, color: style.ink
            )
            .frame(width: 130, height: 40, alignment: .topLeading)
            .offset(x: 323.75, y: 211)
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    private func indicator(_ text: String, leading: CGFloat, centerY: CGFloat, tracking: CGFloat = 1) -> some View {
        Text(text)
            .font(CaseFont.custom(CaseFont.michroma, 14.4))
            .tracking(tracking)
            .foregroundStyle(style.ink)
            .emboldened(0.5)
            .scaleEffect(x: 0.82, y: 1, anchor: .leading)
            .place(leading: leading, centerY: centerY, width: 60)
    }

    // MARK: Date

    /// Day first ("28. 6") unless the locale writes the month first (" 6-28"), like the watch's
    /// date-format setting.
    static func dateText(_ date: Date, calendar: Calendar, dayFirst: Bool) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        let day = DisplayParts.twoCells(components.day ?? 1, blank: " "),
            month = DisplayParts.twoCells(components.month ?? 1, blank: " ")
        return dayFirst ? day + "." + month : month + "-" + day
    }

    static var localeDayFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: .current) ?? "d.M"
        guard let dayIndex = format.firstIndex(of: "d"), let monthIndex = format.firstIndex(of: "M") else {
            return true
        }
        return dayIndex < monthIndex
    }
}
