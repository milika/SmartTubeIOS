import WidgetKit

/// The WidgetKit side of the live clock: hands LiveClock's entry schedule (and the model's light)
/// to WidgetKit. The schedule and its contract with the views live in LiveClock. A face with a
/// step display also gets today's steps (CasioSteps), read when the timeline is made; its timeline
/// is then reloaded every half hour so the steps keep up.
struct CasioClockProvider: TimelineProvider {
    /// The model's widget kind, whose light this timeline follows.
    let model: String
    var usesSteps = false

    /// How often a step face's timeline is remade.
    static let stepsRefresh: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        let now = Date()
        // The gallery shows a step face part way to its goal.
        let steps = usesSteps ? (context.isPreview ? CasioSteps.goal * 7 / 10 : CasioSteps.cached(now: now)) : nil
        completion(CasioClockEntry(date: now, steps: steps))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        let now = Date()
        let entries = LiveClock.entries(from: now, backlightUntil: CasioBacklightIntent.backlightUntil(model: model))
        guard usesSteps else {
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }
        Task {
            let reading = await CasioSteps.current(now: now)
            let withSteps = entries.map { entry in
                var entry = entry
                entry.steps = reading.steps
                return entry
            }
            completion(Timeline(entries: withSteps, policy: .after(now.addingTimeInterval(Self.stepsRefresh))))
        }
    }
}
