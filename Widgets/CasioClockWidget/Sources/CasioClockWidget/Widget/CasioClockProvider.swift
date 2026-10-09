import WidgetKit

struct CasioClockEntry: TimelineEntry {
    let date: Date
    var backlit = false
}

struct CasioClockProvider: TimelineProvider {
    /// The model's widget kind, whose light this timeline follows.
    let model: String

    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        let entries = Self.entries(from: Date(), backlightUntil: CasioBacklightIntent.backlightUntil(model: model))
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
