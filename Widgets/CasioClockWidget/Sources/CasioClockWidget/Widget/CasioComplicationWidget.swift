#if os(watchOS)
import SwiftUI
import WidgetKit

/// A model's rectangular Apple Watch complication (Modular faces, Smart Stack). Watch
/// complications can't run a tap action, so there is no light; a tap opens the watch app.
/// Internal: the catalogue publishes them all (CasioWidgets.complications).
struct CasioComplicationWidget<Model: CasioComplicationModel>: Widget {
    var body: some WidgetConfiguration {
        let provider = CasioClockProvider(model: Model.complicationKind)
        return StaticConfiguration(kind: Model.complicationKind, provider: provider) { entry in
            Model.rectangularComplication(CasioFaceContext(date: entry.date))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Model.complicationName)
        .description(Model.complicationSummary)
        .supportedFamilies([.accessoryRectangular])
    }
}
#endif
