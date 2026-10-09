import SwiftUI
import WidgetKit

// The iPhone widget (systemSmall doesn't exist on watchOS).
#if !os(watchOS)
/// Casio A158W: list `CasioA158WWidget()` in a WidgetBundle.
public struct CasioA158WWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioA158W>().body }
}

// Xcode canvas: tune the face live (normal and lit).
#Preview("A158W", as: .systemSmall) {
    CasioA158WWidget()
} timeline: {
    CasioClockEntry(date: .now)
    CasioClockEntry(date: .now, backlit: true)
}
#endif
