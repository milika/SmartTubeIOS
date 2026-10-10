import AppIntents
import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)

// How a Casio widget stays live:
// - The hours, date and weekday come from a timeline with one entry per hour (12 at a time,
//   then WidgetKit asks for more; CasioClockProvider).
// - Widgets can't redraw every minute or second, so minutes and seconds are WidgetKit's own
//   timer text ("10:MM:SS"), clipped to the digits each needs (LiveClock, LiveSeconds).
// - Tapping the widget runs CasioBacklightIntent for that model: the LCD lights for 3 s.

/// The small Home Screen widget for one model. Internal: the catalogue publishes them all
/// (CasioWidgets.homeScreen), so the model protocol stays internal.
struct CasioWatchWidget<Model: CasioModel>: Widget, CasioModelWidget {
    var modelKind: String { Model.kind }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Model.kind, provider: CasioClockProvider(model: Model.kind, usesSteps: Model.usesSteps)
        ) { entry in
            Button(intent: CasioBacklightIntent(model: Model.kind)) {
                FaceCanvas(size: Model.canvas, visible: Model.widgetArea) {
                    Model.face(CasioFaceContext(date: entry.date, backlit: entry.backlit, steps: entry.steps))
                }
            }
            .buttonStyle(.plain)
            // LCD digits switch, they don't roll (also at the hourly entry change; see LiveClock).
            .contentTransition(.identity)
            .containerBackground(for: .widget) { Model.caseBackground }
        }
        .configurationDisplayName(Model.displayName)
        .description(Model.summary)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
#endif

/// A catalogue widget, by its model's kind (tests check the catalogue against CasioModels).
protocol CasioModelWidget {
    var modelKind: String { get }
}
