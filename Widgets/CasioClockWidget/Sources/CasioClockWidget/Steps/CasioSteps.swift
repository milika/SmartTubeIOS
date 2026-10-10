import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

/// Today's step count from the Health app, for faces with a step display (the ABL-100WE's bar).
///
/// - The containing app asks for read access to steps (Health's permission sheet can't be shown
///   from a widget).
/// - The widget reads today's total when it builds its timeline. Health data is encrypted while
///   the iPhone is locked, so each good read is also kept (in the widget's own defaults) and used
///   until a new one succeeds, for the same day only.
/// - Health doesn't tell an app whether read access was denied: a denied read looks like a day
///   with no steps.
enum CasioSteps {
    /// The daily goal a full step bar stands for.
    static let goal = 10_000

    /// Today's steps: a fresh read when Health is readable, else the last read today, else nil.
    static func current(
        now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard
    ) async
        -> Int?
    {
        if let fresh = await readToday(now: now, calendar: calendar) {
            store(fresh, at: now, defaults: defaults)
            return fresh
        }
        return cached(now: now, calendar: calendar, defaults: defaults)
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
