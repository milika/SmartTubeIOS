import CasioClockWidget
import SwiftUI

/// The minimal watch app that carries the Casio complication: a live preview and how to add it.
/// No YouTube on the watch.
@main
struct SmartTubeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    CasioF91WComplicationPreview()
                        .frame(height: 64)
                    Text("Casio F-91W complication")
                        .font(.headline)
                    Text(
                        "Touch and hold the watch face, tap Edit, swipe to Complications, choose a large slot and pick SmartTube."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
