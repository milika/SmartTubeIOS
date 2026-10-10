import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

/// Today's step count from the Health app, for faces with a step display (the ABL-100WE's bar).
///
/// - The containing app asks for read access to steps (Health's permission sheet can't be shown
///   from a widget).
/// - The widget reads today's total when it builds its timeline. Health data is encrypted while
///   the iPhone is locked, so a read can fail; the app also reads today's total whenever it comes
///   to the foreground and stores it in the shared App Group (`sharedSuite`, the same keys). The
///   widget shows the highest of its own read and the stored counts from today (a day's steps
///   only grow).
/// - Health doesn't tell an app whether read access was denied: a denied read looks like a day
///   with no steps.
enum CasioSteps {
    /// The daily goal a full step bar stands for.
    static let goal = 10_000

    /// The App Group the app and the widget extension share; the app writes its reads here.
    static let sharedSuite = "group.com.void.smarttube"

    /// Where a step count came from: shown as a three-letter code while the widget is lit
    /// (a diagnostic: tap the widget to see what it read).
    enum Source: String {
        /// Read from Health just now.
        case health = "HEA"
        /// Stored today by the app.
        case app = "APP"
        /// The widget's own earlier read today.
        case widget = "WID"
        /// Nothing known.
        case none = "NON"
    }

    struct Reading: Equatable {
        var steps: Int?
        var source: Source
    }

    /// Today's steps: the highest of a fresh read and today's stored counts (the widget's and the
    /// app's), with where it came from.
    static func current(
        now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard,
        shared: UserDefaults? = UserDefaults(suiteName: sharedSuite)
    ) async -> Reading {
        let fresh = await readToday(now: now, calendar: calendar)
        let ownCached = cached(now: now, calendar: calendar, defaults: defaults)
        if let fresh { store(fresh, at: now, defaults: defaults) }
        let known: [(Int?, Source)] = [
            (fresh, .health), (shared.flatMap { cached(now: now, calendar: calendar, defaults: $0) }, .app),
            (ownCached, .widget),
        ]
        var best = Reading(steps: nil, source: .none)
        for case let (steps?, source) in known where best.steps.map({ steps > $0 }) ?? true {
            best = Reading(steps: steps, source: source)
        }
        return best
    }

    /// The fraction of the goal, 0...1.
    static func progress(_ steps: Int?) -> Double {
        guard let steps, steps > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }

    // MARK: Cache

    static let countKey = "CasioClockWidget.steps.count"
    static let dateKey = "CasioClockWidget.steps.date"

    static func store(_ steps: Int, at date: Date, defaults: UserDefaults = .standard) {
        defaults.set(steps, forKey: countKey)
        defaults.set(date, forKey: dateKey)
    }

    /// The last stored count, if it was read today.
    static func cached(now: Date, calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Int? {
        // The app and the widget store under these keys (the app's copy: CasioWidgetSteps in
        // SmartTubeIOS).
        guard let date = defaults.object(forKey: dateKey) as? Date, calendar.isDate(date, inSameDayAs: now),
            defaults.object(forKey: countKey) != nil
        else { return nil }
        return defaults.integer(forKey: countKey)
    }

    // MARK: Health

    /// Today's total from Health; nil when Health isn't available or can't be read (locked).
    static func readToday(now: Date, calendar: Calendar) async -> Int? {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let start = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum)
        do {
            let statistics = try await descriptor.result(for: HKHealthStore())
            let sum = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            return Int(sum)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
