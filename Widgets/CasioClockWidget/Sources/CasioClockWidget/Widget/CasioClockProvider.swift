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

    /// Hour entries after the light goes off; the timeline then ends and WidgetKit reloads.
    static let litTimelineHours = 2

    /// The hour entries, preceded by a lit entry while the light is on. WidgetKit renders every
    /// entry before it shows the timeline, so the lit timeline is kept short, and the light lasts
    /// its full duration from now rather than from the tap.
    static func entries(from now: Date, backlightUntil: Date?, calendar: Calendar = .current) -> [CasioClockEntry] {
        guard let requested = backlightUntil, requested > now else { return hourEntries(from: now, calendar: calendar) }
        let until = max(requested, now.addingTimeInterval(CasioBacklightIntent.duration))
        return [CasioClockEntry(date: now, backlit: true), CasioClockEntry(date: until)]
            + hourEntries(from: until, count: litTimelineHours + 1, calendar: calendar).filter { $0.date > until }
            .prefix(litTimelineHours)
    }

    /// One entry at the start of the current hour and at each of the next 11 (minutes and seconds
    /// are live, see LiveClock); WidgetKit reloads after 12 hours.
    static func hourEntries(from now: Date, count: Int = 12, calendar: Calendar = .current) -> [CasioClockEntry] {
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: hourStart.addingTimeInterval(Double($0) * 3600)) }
    }
}
