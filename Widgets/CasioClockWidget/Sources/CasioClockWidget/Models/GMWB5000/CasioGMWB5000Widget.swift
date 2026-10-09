import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)
/// G-Shock GMW-B5000: list `CasioGMWB5000Widget()` in a WidgetBundle.
public struct CasioGMWB5000Widget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioGMWB5000>().body }
}

// Xcode canvas: tune the face live (normal and lit).
#Preview("GMW-B5000", as: .systemSmall) {
    CasioGMWB5000Widget()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
