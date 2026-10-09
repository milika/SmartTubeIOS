import CasioClockWidget
import SwiftUI

/// The minimal watch app that carries the Casio complications: live previews and how to add them.
/// No YouTube on the watch.
@main
struct SmartTubeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    CasioComplicationGallery()
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
