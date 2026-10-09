import AppIntents
import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)

// How a Casio widget stays live:
// - Hours and minutes come from a timeline with one entry per minute (an hour of entries,
//   then WidgetKit asks for the next hour), so the display changes exactly on the minute.
// - Widgets can't redraw every second, so the seconds are WidgetKit's own timer text
//   counting up from the start of the minute, clipped to its last two digits (LiveSeconds).
// - Tapping the widget runs CasioBacklightIntent for that model: the LCD lights for 3 s.

/// The small Home Screen widget for one model. Internal: each model exposes a public wrapper
/// (see CasioF91WWidget) so the model protocol stays internal.
struct CasioWatchWidget<Model: CasioModel>: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Model.kind, provider: CasioClockProvider(model: Model.kind)) { entry in
            Button(intent: CasioBacklightIntent(model: Model.kind)) {
                FaceCanvas(size: Model.canvas) {
                    Model.face(CasioFaceContext(date: entry.date, backlit: entry.backlit))
                }
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { Model.caseBackground }
        }
        .configurationDisplayName(Model.displayName)
        .description(Model.summary)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
#endif
