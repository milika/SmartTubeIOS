import CoreText
import SwiftUI
import WidgetKit

// MARK: - CasioClockWidget (experimental)
//
// A small Home Screen widget that is a live clock drawn as a Casio F-91W.
//
// How it stays live:
// - Hours and minutes come from a timeline with one entry per minute (an hour of entries,
//   then WidgetKit asks for the next hour), so the display changes exactly on the minute.
// - Widgets can't redraw every second, so the seconds are WidgetKit's own timer text
//   counting up from the start of the minute, clipped to its last two digits ("0:23" shows
//   as "23"). All LCD characters use the bundled F91WSegment font (Tools/make_segment_font.py)
//   so the live seconds match the rest of the display.

public struct CasioClockWidget: Widget {
    public static let kind = "CasioClockWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CasioClockProvider()) { entry in
            CasioWatchFace(date: entry.date)
                .containerBackground(for: .widget) { CasioWatchFace.resin }
        }
        .configurationDisplayName("Casio F-91W")
        .description("A live digital clock in the style of the Casio F-91W.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct CasioClockEntry: TimelineEntry {
    let date: Date
}

struct CasioClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        completion(Timeline(entries: Self.minuteEntries(from: Date()), policy: .atEnd))
    }

    /// One entry at the start of the current minute and at each of the next 59.
    static func minuteEntries(from now: Date, count: Int = 60, calendar: Calendar = .current) -> [CasioClockEntry] {
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: minuteStart.addingTimeInterval(Double($0) * 60)) }
    }
}

// MARK: - LCD font

enum F91WFont {
    static let postScriptName = "F91WSegment-Regular"

    private static let registered: Bool = {
        guard let url = Bundle.module.url(forResource: "F91WSegment", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// The font whose glyphs are `height` points tall (glyph height is 0.7 em).
    static func lcd(height: CGFloat) -> Font {
        _ = registered
        return .custom(postScriptName, fixedSize: height / 0.7)
    }
}

// MARK: - Watch face
//
// Laid out on a fixed 594×530 canvas whose coordinates were measured from a front-on photo of
// an F-91W (Wikimedia Commons, Casio_F-91W_5051.jpg), then scaled to the widget. Printed text
// is Eurostile Extended / Microgramma on the watch; SF Pro Expanded is the closest system face.

struct CasioWatchFace: View {
    let date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = CasioWatchFace.localeUses12HourClock

    static let canvas = CGSize(width: 594, height: 530)

    static let resin = LinearGradient(
        colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
    static let blue = Color(red: 0.13, green: 0.40, blue: 0.86)
    static let silver = Color(white: 0.80)
    static let gold = Color(red: 0.91, green: 0.76, blue: 0.29)
    static let printWhite = Color(white: 0.94)
    static let red = Color(red: 0.89, green: 0.15, blue: 0.17)
    static let lcdGlass = Color(red: 0.77, green: 0.79, blue: 0.75)
    static let lcdInk = Color(red: 0.12, green: 0.15, blue: 0.13)

    static var localeUses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                bezel
                printedFace
                lcd
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Bezel and frame lines

    private var bezel: some View {
        ZStack(alignment: .topLeading) {
            // The bright blue ring.
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .strokeBorder(Self.blue, lineWidth: 9)
                .frame(width: 550, height: 470)
                .offset(x: 22, y: 30)
            // The thin silver line framing the printed face.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Self.silver, lineWidth: 2.5)
                .frame(width: 493, height: 412)
                .offset(x: 52, y: 58)
        }
    }

    // MARK: Printed text and bars

    private var printedFace: some View {
        ZStack(alignment: .topLeading) {
            // CASIO / F-91W
            Text("CASIO")
                .font(.system(size: 31, weight: .bold).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(centerX: 195, centerY: 91)
            Text("F-91W")
                .font(.system(size: 25.5, weight: .black).width(.expanded))
                .foregroundStyle(Self.gold)
                .oblique()
                .place(centerX: 397, centerY: 91)
            bar(x: 70, y: 124, width: 450)

            // ◀ LIGHT   ALARM CHRONOGRAPH
            Pointer(left: true).fill(Self.red).frame(width: 16, height: 7).position(x: 96, y: 155)
            Text("LIGHT")
                .font(.system(size: 14, weight: .medium).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(leading: 116, centerY: 155)
            Text("ALARM CHRONOGRAPH")
                .font(.system(size: 17.5, weight: .semibold).width(.expanded))
                .foregroundStyle(Self.gold)
                .place(trailing: 497, centerY: 154, width: 290)

            // ◀ MODE   ALARM ON·OFF/24HR ▶
            Pointer(left: true).fill(Self.red).frame(width: 18, height: 7).position(x: 97, y: 400)
            Text("MODE")
                .font(.system(size: 15.5, weight: .medium).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(leading: 116, centerY: 400)
            Text("ALARM ON·OFF/24HR")
                .font(.system(size: 16.5, weight: .medium).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(trailing: 472, centerY: 400, width: 240)
            Pointer(left: false).fill(Self.red).frame(width: 18, height: 7).position(x: 491, y: 400)

            // WATER [WR] RESIST
            bar(x: 70, y: 417, width: 152, height: 5)
            bar(x: 365, y: 417, width: 155, height: 5)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Self.blue, lineWidth: 4)
                .frame(width: 143, height: 48)
                .offset(x: 222, y: 412)
            Text("WR")
                .font(.system(size: 31, weight: .heavy).width(.expanded))
                .foregroundStyle(Self.red)
                .oblique()
                .place(centerX: 294, centerY: 437)
            Text("WATER")
                .font(.system(size: 24.5, weight: .bold).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(centerX: 155, centerY: 438, width: 120)
            Text("RESIST")
                .font(.system(size: 24.5, weight: .bold).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(centerX: 435, centerY: 438, width: 130)
            Text("u")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Self.printWhite.opacity(0.85))
                .place(centerX: 455, centerY: 461)
        }
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 6) -> some View {
        Rectangle().fill(Self.blue).frame(width: width, height: height).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let parts = Self.displayParts(for: date, calendar: calendar, twelveHour: uses12HourClock)
        return ZStack(alignment: .topLeading) {
            // Silver frame, dark surround, grey-green glass.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Self.silver, lineWidth: 2)
                )
                .frame(width: 409, height: 204)
                .offset(x: 88, y: 176)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Self.lcdGlass, Self.lcdGlass.opacity(0.9)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 389, height: 184)
                .offset(x: 98, y: 186)

            Group {
                // PM in the afternoon on a 12-hour clock; 24H on a 24-hour clock, like the watch.
                if let marker = parts.marker {
                    Text(marker)
                        .font(.system(size: 22, weight: .bold))
                        .place(centerX: 140, centerY: 241)
                }
                // Day of week and date share the top row.
                Text(parts.weekday)
                    .font(F91WFont.lcd(height: 35))
                    .place(leading: 232, baseline: 240, glyphHeight: 35)
                Text(parts.day)
                    .font(F91WFont.lcd(height: 42))
                    .place(trailing: 474, baseline: 247, glyphHeight: 42, width: 110)
                // H:MM
                Text(parts.hoursMinutes)
                    .font(F91WFont.lcd(height: 84))
                    .place(trailing: 380, baseline: 352, glyphHeight: 84, width: 300)
                seconds
            }
            .foregroundStyle(Self.lcdInk)
        }
    }

    /// Live seconds: timer text counting up from the start of this minute ("0:23"), shown
    /// through a right-aligned window that keeps only the last two digits.
    private var seconds: some View {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let glyph: CGFloat = 60
        let digitAdvance = glyph / 0.7 * 0.5
        return Text(minuteStart, style: .timer)
            .font(F91WFont.lcd(height: glyph))
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: digitAdvance * 6, alignment: .trailing)
            .frame(width: digitAdvance * 2, alignment: .trailing)
            .clipped()
            .place(trailing: 476, baseline: 352, glyphHeight: glyph, width: digitAdvance * 2)
    }

    // MARK: Formatting

    struct DisplayParts: Equatable {
        /// "H:MM" with a figure space for a blank leading hour digit ("\u{2007}6:04").
        let hoursMinutes: String
        let isPM: Bool
        /// "PM", "24H" or nil (morning on a 12-hour clock).
        let marker: String?
        let weekday: String
        /// Right-aligned day of month ("\u{2007}9", "26").
        let day: String
    }

    static let weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    static let figureSpace = "\u{2007}"

    static func displayParts(for date: Date, calendar: Calendar, twelveHour: Bool) -> DisplayParts {
        let c = calendar.dateComponents([.hour, .minute, .weekday, .day], from: date)
        let hour24 = c.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        // Like the watch, a 12-hour time has no leading zero ("6:04", not "06:04").
        let hourText = hour < 10 ? (twelveHour ? figureSpace : "0") + "\(hour)" : "\(hour)"
        let minute = c.minute ?? 0
        let dayOfMonth = c.day ?? 1
        return DisplayParts(
            hoursMinutes: hourText + ":" + (minute < 10 ? "0" : "") + "\(minute)",
            isPM: twelveHour && hour24 >= 12,
            marker: twelveHour ? (hour24 >= 12 ? "PM" : nil) : "24H",
            weekday: weekdays[((c.weekday ?? 1) - 1) % 7],
            day: (dayOfMonth < 10 ? figureSpace : "") + "\(dayOfMonth)"
        )
    }
}

/// The small red triangles beside LIGHT, MODE and 24HR.
private struct Pointer: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if left {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Placement on the canvas

extension View {
    /// Slants the view like the printed italics ("F-91W", "WR"). SF Pro Expanded has no
    /// italic face, so `.italic()` would draw it upright.
    fileprivate func oblique() -> some View {
        self.transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.21, d: 1, tx: 6, ty: 0))
    }

    /// Centers the view at a canvas point.
    fileprivate func place(centerX: CGFloat, centerY: CGFloat, width: CGFloat? = nil) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: true)
            .position(x: centerX, y: centerY)
    }

    /// Text starting at `leading`, vertically centered on `centerY`.
    fileprivate func place(leading: CGFloat, centerY: CGFloat, width: CGFloat = 200) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .leading)
            .position(x: leading + width / 2, y: centerY)
    }

    /// Text ending at `trailing`, vertically centered on `centerY`.
    fileprivate func place(trailing: CGFloat, centerY: CGFloat, width: CGFloat) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .trailing)
            .position(x: trailing - width / 2, y: centerY)
    }

    /// LCD text (F91WSegment: line box = 1 em, baseline 0.8 em from the top) starting at
    /// `leading` with its baseline at `baseline`.
    fileprivate func place(leading: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, width: CGFloat = 200)
        -> some View
    {
        let em = glyphHeight / 0.7
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .leading)
            .position(x: leading + width / 2, y: baseline - 0.8 * em + em / 2)
    }

    /// LCD text ending at `trailing` with its baseline at `baseline`.
    fileprivate func place(trailing: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / 0.7
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .trailing)
            .position(x: trailing - width / 2, y: baseline - 0.8 * em + em / 2)
    }
}
