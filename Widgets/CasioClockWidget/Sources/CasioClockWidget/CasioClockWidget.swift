import AppIntents
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
// - Tapping the widget runs CasioBacklightIntent: like pressing LIGHT on the watch, the LCD
//   glows green for a few seconds.

public struct CasioClockWidget: Widget {
    public static let kind = "CasioClockWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CasioClockProvider()) { entry in
            Button(intent: CasioBacklightIntent()) {
                CasioWatchFace(date: entry.date, backlit: entry.backlit)
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { CasioWatchFace.resin }
        }
        .configurationDisplayName("Casio F-91W")
        .description("A live digital clock in the style of the Casio F-91W. Tap it for the light.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Backlight

/// Turns the LCD light on for a few seconds, like the watch's LIGHT button.
public struct CasioBacklightIntent: AppIntent {
    public static let title: LocalizedStringResource = "Casio Light"
    public static let description = IntentDescription("Lights up the Casio F-91W widget for a few seconds.")
    public static let isDiscoverable = false

    static let duration: TimeInterval = 3
    static let defaultsKey = "CasioClockWidget.backlightUntil"

    public init() {}

    public func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget's timeline after a widget intent runs.
        UserDefaults.standard.set(Date().addingTimeInterval(Self.duration), forKey: Self.defaultsKey)
        return .result()
    }

    static func backlightUntil(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: defaultsKey) as? Date
    }
}

// MARK: - Timeline

struct CasioClockEntry: TimelineEntry {
    let date: Date
    var backlit = false
}

struct CasioClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        let entries = Self.entries(from: Date(), backlightUntil: CasioBacklightIntent.backlightUntil())
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Minute entries after the light goes off; the timeline then ends and WidgetKit reloads the
    /// normal hour of minutes.
    static let litTimelineMinutes = 3

    /// The minute entries, preceded by a lit entry while the light is on. WidgetKit renders every
    /// entry before it shows the timeline, so the lit timeline is kept short (an hour of entries
    /// took ~1.8 s on the simulator, most of the light), and the light lasts its full duration
    /// from now rather than from the tap.
    static func entries(from now: Date, backlightUntil: Date?, calendar: Calendar = .current) -> [CasioClockEntry] {
        guard let requested = backlightUntil, requested > now else { return minuteEntries(from: now, calendar: calendar) }
        let until = max(requested, now.addingTimeInterval(CasioBacklightIntent.duration))
        return [CasioClockEntry(date: now, backlit: true), CasioClockEntry(date: until)]
            + minuteEntries(from: until, count: litTimelineMinutes + 1, calendar: calendar).filter { $0.date > until }
                .prefix(litTimelineMinutes)
    }

    /// One entry at the start of the current minute and at each of the next 59.
    static func minuteEntries(from now: Date, count: Int = 60, calendar: Calendar = .current) -> [CasioClockEntry] {
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: minuteStart.addingTimeInterval(Double($0) * 60)) }
    }
}

// MARK: - Watch face
//
// Laid out on a fixed 594×530 canvas whose coordinates were measured from a front-on photo of
// an F-91W (Wikimedia Commons, Casio_F-91W_5051.jpg), then scaled to the widget.
// Typefaces per Fonts In Use (fontsinuse.com/uses/74290): CASIO logo Microgramma; "F-91W"
// Neue Helvetica Extended Black; "ALARM CHRONOGRAPH" regular-width Medium; the other labels
// Eurostile Extended Regular / Medium. Free look-alikes (SIL OFL, Google Fonts) stand in:
// Michroma for Microgramma / Eurostile Extended, Archivo Expanded Black (an instance of
// Archivo's variable font) for Neue Helvetica Extended Black, Saira Medium for Eurostile Medium,
// Saira Expanded SemiBold (an instance of Saira's variable font) for the WR mark.

struct CasioWatchFace: View {
    let date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = DisplayParts.localeUses12HourClock
    var style = LCDStyle()
    /// The LIGHT button's green backlight.
    var backlit = false
    /// Fixed seconds instead of the live timer (static previews; the timer only animates
    /// inside a widget).
    var previewSeconds: Int? = nil

    static let canvas = CGSize(width: 594, height: 530)

    static let resin = LinearGradient(
        colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
    // Colours sampled from the photo, white-balanced so the white print is neutral.
    static let blue = Color(red: 0.04, green: 0.45, blue: 0.95)
    static let silver = Color(white: 0.86)
    static let gold = Color(red: 0.90, green: 0.78, blue: 0.40)
    static let printWhite = Color(white: 0.94)
    static let red = Color(red: 0.95, green: 0.13, blue: 0.13)

    var body: some View {
        FaceCanvas(size: Self.canvas) {
            bezel
            printedFace
            lcd
        }
    }

    // Case print fonts (Resources/).
    private static func michroma(_ size: CGFloat) -> Font { CaseFont.custom("Michroma-Regular", size) }
    private static func archivoBlack(_ size: CGFloat) -> Font { CaseFont.custom("ArchivoExpanded-Black", size) }
    private static func saira(_ size: CGFloat) -> Font { CaseFont.custom("Saira-Medium", size) }
    private static func sairaExpanded(_ size: CGFloat) -> Font { CaseFont.custom("SairaExpanded-SemiBold", size) }

    // MARK: Bezel and frame lines

    private var bezel: some View {
        ZStack(alignment: .topLeading) {
            // Thin outer blue line, wide blue band, white line framing the printed face; all three
            // are octagons with the watch's cut corners.
            frameLine(x: 23.5, y: 31.5, width: 548.5, height: 472, lineWidth: 3, radius: 24, color: Self.blue)
            frameLine(x: 36, y: 45.5, width: 520.5, height: 445, lineWidth: 10.5, radius: 22, color: Self.blue)
            frameLine(x: 50, y: 60, width: 492, height: 417, lineWidth: 2, radius: 18, color: Self.silver)
        }
    }

    /// A frame line stroked along the given centerline rectangle.
    private func frameLine(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, lineWidth: CGFloat, radius: CGFloat, color: Color
    ) -> some View {
        CutCornerRect(cut: CGSize(width: 40, height: 64), radius: radius)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    // MARK: Printed text and bars

    private var printedFace: some View {
        ZStack(alignment: .topLeading) {
            // CASIO / F-91W
            Text("CASIO")
                .font(Self.michroma(25.5))
                .tracking(4)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.6)
                .place(centerX: 199.5, centerY: 91.75)
            Text("F-91W")
                .font(Self.archivoBlack(23.6))
                .tracking(5.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.6)
                .oblique()
                .place(centerX: 398, centerY: 93.5)
            bar(x: 70, y: 125, width: 453)

            // ◀ LIGHT   ALARM  CHRONOGRAPH
            Pointer(left: true).fill(Self.red).frame(width: 21, height: 7).position(x: 96.75, y: 157.75)
            Text("LIGHT")
                .font(Self.michroma(12.4))
                .tracking(1)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 157)
            Text("ALARM")
                .font(Self.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.25)
                .place(leading: 227.5, centerY: 154.75, width: 100)
            Text("CHRONOGRAPH")
                .font(Self.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.25)
                .place(trailing: 504.5, centerY: 154.75, width: 200)

            // ◀ MODE   ALARM  ON · OFF / 24HR ▶
            Pointer(left: true).fill(Self.red).frame(width: 20, height: 6.5).position(x: 98, y: 404.5)
            Text("MODE")
                .font(Self.michroma(12.8))
                .tracking(1.1)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 402.75)
            Text("ALARM")
                .font(Self.michroma(12.8))
                .tracking(0.85)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 242.75, centerY: 402.75, width: 90)
            Text("ON · OFF / 24HR")
                .font(Self.michroma(12.8))
                .tracking(0.65)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(trailing: 476.3, centerY: 402.75, width: 170)
            Pointer(left: false).fill(Self.red).frame(width: 20.5, height: 7).position(x: 497.25, y: 404.25)

            // WATER [WR] RESIST
            bar(x: 70, y: 419, width: 144.5, height: 5.5)
            bar(x: 375, y: 419, width: 148.5, height: 5.5)
            // The WR box: round top corners, cut bottom corners.
            CutCornerRect(cut: CGSize(width: 11, height: 11), bottomCut: CGSize(width: 15, height: 15), radius: 8)
                .stroke(Self.blue, lineWidth: 3.75)
                .frame(width: 140.6, height: 47)
                .offset(x: 226.6, y: 417.6)
            // The watch's WR is wider than any free extended face; Saira Expanded is stretched.
            Text("WR")
                .font(Self.sairaExpanded(33.8))
                .foregroundStyle(Self.red)
                .oblique()
                .scaleEffect(x: 1.6, y: 1)
                .place(centerX: 295.25, centerY: 441.75)
            Text("WATER")
                .font(Self.michroma(17))
                .tracking(3.35)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.3)
                .place(centerX: 158, centerY: 441.5, width: 130)
            Text("RESIST")
                .font(Self.michroma(17))
                .tracking(4.2)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.5)
                .place(centerX: 441, centerY: 441.5, width: 130)
            Text("u")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.printWhite.opacity(0.85))
                .place(centerX: 459.5, centerY: 463)
        }
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 6) -> some View {
        Rectangle().fill(Self.blue).frame(width: width, height: height).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let parts = DisplayParts.make(
            for: date, calendar: calendar, twelveHour: uses12HourClock, blankDigit: style.digits.blankDigit)
        return ZStack(alignment: .topLeading) {
            // Silver outline, dark surround, grey-green glass.
            LCDWindow(
                frame: CGRect(x: 89, y: 174, width: 414.5, height: 214), outline: Self.silver,
                glass: CGRect(x: 104, y: 191.5, width: 389.5, height: 184.5), backlit: backlit, style: style)

            // PM in the afternoon on a 12-hour clock; 24H on a 24-hour clock, like the watch.
            if let marker = parts.marker {
                Text(marker)
                    .font(.system(size: 29.3, weight: .bold))
                    .foregroundStyle(style.ink)
                    .place(centerX: 141, centerY: 243.5)
            }
            // Day of week and date share the top row.
            LCDText(
                text: parts.weekday, font: style.letters, glyph: 43, edge: .leading(234), baseline: 247, tracking: 7.5,
                style: style)
            LCDText(
                text: parts.day, font: style.digits, glyph: 47.5, edge: .trailing(484.7), baseline: 251.5, width: 120,
                tracking: 4.5, style: style)
            // H:MM; the watch's digits are narrower than DSEG's.
            LCDText(
                text: parts.hoursMinutes, font: style.digits, glyph: 88.5, edge: .trailing(383), baseline: 357.5,
                width: 320, xScale: Self.digitSqueeze, style: style)
            LiveSeconds(
                date: date, calendar: calendar, previewSeconds: previewSeconds, glyph: 67, trailing: 486,
                baseline: 357.5, xScale: Self.digitSqueeze, style: style)
        }
    }

    /// Width of the big digits relative to DSEG's (measured from the photo).
    static let digitSqueeze: CGFloat = 0.9

}
