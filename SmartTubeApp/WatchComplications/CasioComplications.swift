import CasioClockWidget
import SwiftUI
import WidgetKit

/// The watch complications: the Casio LCD for Apple's watch faces.
@main
struct CasioComplications: WidgetBundle {
    var body: some Widget {
        CasioF91WComplication()
    }
}
