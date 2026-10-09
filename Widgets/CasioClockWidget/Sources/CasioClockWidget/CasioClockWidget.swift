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
                FaceCanvas(size: CasioF91W.canvas) {
                    CasioF91W.face(CasioFaceContext(date: entry.date, backlit: entry.backlit))
                }
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { CasioF91W.caseBackground }
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
