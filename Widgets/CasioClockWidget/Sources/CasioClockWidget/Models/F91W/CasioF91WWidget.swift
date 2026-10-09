import SwiftUI
import WidgetKit

/// Casio F-91W: list `CasioF91WWidget()` in a WidgetBundle.
public struct CasioF91WWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioF91W>().body }
}
