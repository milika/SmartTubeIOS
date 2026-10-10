#if os(iOS)
import HealthKit
import SwiftUI
import WidgetKit

// MARK: - Casio step widget
//
// The Casio ABL-100WE Home Screen widget (Widgets/CasioClockWidget) fills its step bar toward
// 10,000 steps from the Health app. A widget can't show Health's permission sheet, so the app
// asks for read access to steps here. The widget reads Health itself, but Health is unreadable
// while the iPhone is locked, so the app also reads today's total whenever it is open and stores
// it in the shared App Group for the widget (CasioSteps in the widget package reads the same
// keys).

/// Health access and the shared step count for the Casio widgets' step display.
public enum CasioWidgetSteps {
    /// The widget kind that shows steps.
    static let widgetKind = "CasioABL100WE"
    // Shared with CasioSteps (Widgets/CasioClockWidget): suite and keys must match.
    static let sharedSuite = "group.com.void.smarttube"
    static let countKey = "CasioClockWidget.steps.count"
    static let dateKey = "CasioClockWidget.steps.date"

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks Health for read access to steps (the sheet shows once; later changes are made in
    /// the Health app), then shares today's total with the widget.
    @discardableResult
    static func requestAccess() async -> Int? {
        try? await HKHealthStore().requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount)])
        return await refresh()
    }

    /// Reads today's steps (the app is open, so Health is readable), stores them for the widget
    /// and redraws it. Returns the count, or nil when Health can't be read.
    @discardableResult
    public static func refresh() async -> Int? {
        let steps = await readToday()
        if let steps, let shared = UserDefaults(suiteName: sharedSuite) {
            shared.set(steps, forKey: countKey)
            shared.set(Date(), forKey: dateKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        return steps
    }

    private static func readToday() async -> Int? {
        guard isAvailable else { return nil }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum)
        guard let statistics = try? await descriptor.result(for: HKHealthStore()) else { return nil }
        return Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
    }
}

/// Settings section: gives the step widget access to Health and shows what Health returns today.
struct WidgetStepsSection: View {
    @State private var steps: Int?

    var body: some View {
        Section {
            Button("Show Steps on the Casio ABL-100WE Widget") {
                Task { steps = await CasioWidgetSteps.requestAccess() }
            }
            .disabled(!CasioWidgetSteps.isAvailable)
            if let steps {
                LabeledContent("Steps Today", value: steps.formatted())
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text(
                "The Casio ABL-100WE widget fills its step bar toward 10,000 steps a day, using your step count from the Health app. Your steps stay on this iPhone. If Steps Today shows 0 while you have steps, allow Steps for SmartTube in the Health app, under Sharing, then Apps."
            )
        }
        .task { steps = await CasioWidgetSteps.refresh() }
    }
}
#endif
