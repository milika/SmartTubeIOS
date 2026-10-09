import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)

/// Casio F-91W: list `CasioF91WWidget()` in a WidgetBundle.
public struct CasioF91WWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioF91W>().body }
}

// Xcode canvas: tune the face live (normal and lit). Copy this for a new model.
#Preview("F-91W", as: .systemSmall) {
    CasioF91WWidget()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
