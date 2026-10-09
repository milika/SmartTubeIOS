import WidgetKit

/// The WidgetKit side of the live clock: hands LiveClock's entry schedule (and the model's light)
/// to WidgetKit. The schedule and its contract with the views live in LiveClock.
struct CasioClockProvider: TimelineProvider {
    /// The model's widget kind, whose light this timeline follows.
    let model: String

    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        let entries = LiveClock.entries(from: Date(), backlightUntil: CasioBacklightIntent.backlightUntil(model: model))
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
