import SwiftUI
import WidgetKit

/// The F-91W complication as a plain view, live to the minute (the watch app shows it as a preview).
public struct CasioF91WComplicationPreview: View {
    public init() {}
    public var body: some View {
        TimelineView(.everyMinute) { tl in
            CasioF91W.rectangularComplication(CasioFaceContext(date: tl.date))
        }
    }
}

#if os(watchOS)
/// Casio F-91W rectangular complication: list `CasioF91WComplication()` in a watchOS WidgetBundle.
public struct CasioF91WComplication: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioComplicationWidget<CasioF91W>().body }
}

#Preview("F-91W", as: .accessoryRectangular) {
    CasioF91WComplication()
} timeline: {
    CasioClockEntry(date: .now)
}
#endif
