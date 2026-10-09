import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)
/// G-Shock DW-5000C: list `CasioDW5000CWidget()` in a WidgetBundle.
public struct CasioDW5000CWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioDW5000C>().body }
}

// Xcode canvas: tune the face live (normal and lit).
#Preview("DW-5000C", as: .systemSmall) {
    CasioDW5000CWidget()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
