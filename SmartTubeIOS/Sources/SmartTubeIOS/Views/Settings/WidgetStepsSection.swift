#if os(iOS)
import HealthKit
import SwiftUI
import WidgetKit

// MARK: - Casio step widget
//
// The Casio ABL-100WE Home Screen widget (Widgets/CasioClockWidget) fills its step bar toward
// 10,000 steps from the Health app. A widget can't show Health's permission sheet, so the app
// asks for read access to steps here; the widget then reads today's total itself.

/// Health access for the Casio widgets' step display.
public enum CasioWidgetSteps {
    /// The widget kind that shows steps.
    static let widgetKind = "CasioABL100WE"

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks Health for read access to steps (the sheet shows once; later changes are made in
    /// the Health app), then redraws the widget.
    static func requestAccess() async {
        try? await HKHealthStore().requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount)])
        refreshWidget()
    }

    /// Redraws the step widget so it picks up today's steps (the app is open, so Health is
    /// readable).
    public static func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

/// Settings section: lets the user give the step widget access to Health.
struct WidgetStepsSection: View {
    var body: some View {
        Section {
            Button("Show Steps on the Casio ABL-100WE Widget") {
                Task { await CasioWidgetSteps.requestAccess() }
            }
            .disabled(!CasioWidgetSteps.isAvailable)
        } header: {
            Text("Widgets")
        } footer: {
            Text(
                "The Casio ABL-100WE widget fills its step bar toward 10,000 steps a day, using your step count from the Health app. Your steps stay on this iPhone. To change access later, open the Health app, then Sharing, then Apps."
            )
        }
    }
}
#endif
