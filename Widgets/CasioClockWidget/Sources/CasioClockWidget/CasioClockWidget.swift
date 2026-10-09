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
//   as "23"). All LCD characters use the bundled DSEG fonts so the live seconds match the
//   rest of the display.

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

// MARK: - LCD fonts
//
// DSEG7 / DSEG14 Classic Bold Italic by Keshikan (SIL OFL 1.1, Resources/DSEG-LICENSE.txt)
// for digits and letters.

struct LCDFont: Equatable {
    let postScriptName: String
    /// Glyph height as a fraction of the em.
    let glyphToEm: CGFloat
    /// Baseline position from the top of the line box, in ems.
    let baselineFromTop: CGFloat
    /// Advance of one digit, in ems.
    let digitAdvance: CGFloat
    /// A character with every segment lit ("8" / "~"), for the faint unlit segments; nil if none.
    let allSegments: Character?
    /// A digit-wide blank ("!" in DSEG), for an empty leading hour digit.
    let blankDigit: String

    static func dseg7(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG7Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "8", blankDigit: "!")
    }
    static func dseg14(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG14Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "~", blankDigit: "!")
    }

    private static let registered: Bool = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// The font whose glyphs are `height` points tall.
    func font(height: CGFloat) -> Font {
        _ = Self.registered
        return .custom(postScriptName, fixedSize: height / glyphToEm)
    }

    /// `text` with every character replaced by the all-segments glyph (digits by `allSegments`,
    /// keeping colons), for the unlit-segment layer.
    func allLit(_ text: String) -> String? {
        guard let allSegments else { return nil }
        return String(text.map { $0 == ":" ? ":" : allSegments })
    }
}

/// Look options for the face; the widget uses `.standard` (chosen from prototypes: DSEG Bold
/// Italic with unlit segments on grey-green glass).
struct CasioFaceStyle {
    var digits: LCDFont = .dseg7("BoldItalic")
    var letters: LCDFont = .dseg14("BoldItalic")
    /// Opacity of the unlit segments behind the digits; 0 = off.
    var unlitOpacity: Double = 0.08
    var glass: Color = Color(red: 0.77, green: 0.79, blue: 0.75)
    var ink: Color = Color(red: 0.12, green: 0.15, blue: 0.13)

    static let standard = CasioFaceStyle()
}

// MARK: - Watch face
//
// Laid out on a fixed 594×530 canvas whose coordinates were measured from a front-on photo of
// an F-91W (Wikimedia Commons, Casio_F-91W_5051.jpg), then scaled to the widget.
// Typefaces per Fonts In Use (fontsinuse.com/uses/74290): CASIO logo Microgramma; "F-91W"
// Neue Helvetica Extended Black; "ALARM CHRONOGRAPH" regular-width Medium; the other labels
// Eurostile Extended Regular / Medium. SF Pro Expanded stands in for the extended faces.

struct CasioWatchFace: View {
    let date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = CasioWatchFace.localeUses12HourClock
    var style: CasioFaceStyle = .standard
    /// Fixed seconds instead of the live timer (static previews; the timer only animates
    /// inside a widget).
    var previewSeconds: Int? = nil

    static let canvas = CGSize(width: 594, height: 530)

    static let resin = LinearGradient(
        colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
    static let blue = Color(red: 0.13, green: 0.40, blue: 0.86)
    static let silver = Color(white: 0.80)
    static let gold = Color(red: 0.91, green: 0.76, blue: 0.29)
    static let printWhite = Color(white: 0.94)
    static let red = Color(red: 0.89, green: 0.15, blue: 0.17)

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
                .font(.system(size: 14, weight: .regular).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(leading: 116, centerY: 155)
            Text("ALARM CHRONOGRAPH")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Self.gold)
                .place(trailing: 497, centerY: 154, width: 290)

            // ◀ MODE   ALARM ON·OFF/24HR ▶
            Pointer(left: true).fill(Self.red).frame(width: 18, height: 7).position(x: 97, y: 400)
            Text("MODE")
                .font(.system(size: 15.5, weight: .regular).width(.expanded))
                .foregroundStyle(Self.printWhite)
                .place(leading: 116, centerY: 400)
            Text("ALARM ON·OFF/24HR")
                .font(.system(size: 16.5, weight: .regular).width(.expanded))
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
        let parts = Self.displayParts(
            for: date, calendar: calendar, twelveHour: uses12HourClock, blankDigit: style.digits.blankDigit)
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
                        colors: [style.glass, style.glass.opacity(0.9)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 389, height: 184)
                .offset(x: 98, y: 186)

            // PM in the afternoon on a 12-hour clock; 24H on a 24-hour clock, like the watch.
            if let marker = parts.marker {
                Text(marker)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(style.ink)
                    .place(centerX: 140, centerY: 241)
            }
            // Day of week and date share the top row.
            lcdText(parts.weekday, font: style.letters, glyph: 35, leading: 232, baseline: 240)
            lcdText(parts.day, font: style.digits, glyph: 42, trailing: 474, baseline: 247, width: 110)
            // H:MM
            lcdText(parts.hoursMinutes, font: style.digits, glyph: 76, trailing: 384, baseline: 352, width: 300)
            seconds
        }
    }

    /// LCD text with its unlit segments faintly behind it.
    @ViewBuilder
    private func lcdText(
        _ text: String, font: LCDFont, glyph: CGFloat, leading: CGFloat? = nil, trailing: CGFloat? = nil,
        baseline: CGFloat, width: CGFloat = 200
    ) -> some View {
        let layers: [(String, Double)] =
            [(font.allLit(text), style.unlitOpacity), (text, 1)].compactMap { item in
                guard let t = item.0, item.1 > 0 else { return nil }
                return (t, item.1)
            }
        ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
            let view = Text(layer.0).font(font.font(height: glyph)).foregroundStyle(style.ink.opacity(layer.1))
            if let leading {
                view.place(leading: leading, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            } else if let trailing {
                view.place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            }
        }
    }

    /// Live seconds: timer text counting up from the start of this minute ("0:23"), shown
    /// through a right-aligned window that keeps only the last two digits.
    private var seconds: some View {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let glyph: CGFloat = 54
        let font = style.digits
        let digitAdvance = glyph / font.glyphToEm * font.digitAdvance
        let live: Text =
            previewSeconds.map { Text(String(format: "%02d", $0)) } ?? Text(minuteStart, style: .timer)
        return ZStack(alignment: .topLeading) {
            if style.unlitOpacity > 0, let lit = font.allLit("00") {
                Text(lit).font(font.font(height: glyph))
                    .foregroundStyle(style.ink.opacity(style.unlitOpacity))
                    .place(trailing: 476, baseline: 352, glyphHeight: glyph, font: font, width: digitAdvance * 2.02)
            }
            live
                .font(font.font(height: glyph))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: digitAdvance * 6, alignment: .trailing)
                .frame(width: digitAdvance * 2.02, alignment: .trailing)
                .clipped()
                .place(trailing: 476, baseline: 352, glyphHeight: glyph, font: font, width: digitAdvance * 2.02)
        }
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

    static func displayParts(
        for date: Date, calendar: Calendar, twelveHour: Bool, blankDigit: String = figureSpace
    ) -> DisplayParts {
        let c = calendar.dateComponents([.hour, .minute, .weekday, .day], from: date)
        let hour24 = c.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        // Like the watch, a 12-hour time has no leading zero ("6:04", not "06:04").
        let hourText = hour < 10 ? (twelveHour ? blankDigit : "0") + "\(hour)" : "\(hour)"
        let minute = c.minute ?? 0
        let dayOfMonth = c.day ?? 1
        return DisplayParts(
            hoursMinutes: hourText + ":" + (minute < 10 ? "0" : "") + "\(minute)",
            isPM: twelveHour && hour24 >= 12,
            marker: twelveHour ? (hour24 >= 12 ? "PM" : nil) : "24H",
            weekday: weekdays[((c.weekday ?? 1) - 1) % 7],
            day: (dayOfMonth < 10 ? blankDigit : "") + "\(dayOfMonth)"
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

    /// LCD text starting at `leading` with its baseline at `baseline`.
    fileprivate func place(leading: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .leading)
            .position(x: leading + width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }

    /// LCD text ending at `trailing` with its baseline at `baseline`.
    fileprivate func place(trailing: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .trailing)
            .position(x: trailing - width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }
}
