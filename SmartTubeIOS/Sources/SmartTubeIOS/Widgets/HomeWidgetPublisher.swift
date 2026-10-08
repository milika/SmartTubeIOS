#if os(iOS)
import Foundation
import SmartTubeIOSCore
import WidgetKit
import os

private let widgetLog = Logger(subsystem: "com.void.smarttube.app", category: "HomeWidget")

// MARK: - HomeWidgetPublisher (task #353)
//
// Writes the Home page's first videos into the App Group snapshot the Home Screen widget
// reads (see HomeWidgetSnapshot.swift), then asks WidgetKit to reload it.

@MainActor
public enum HomeWidgetPublisher {
    private static var saveTask: Task<Void, Never>?

    /// Hooks the publisher to `browseViewModel` so every Home load refreshes the widget.
    public static func attach(to browseViewModel: BrowseViewModel) {
        browseViewModel.onHomeLoaded = { videos in publish(videos) }
    }

    static func publish(_ videos: [Video]) {
        guard let store = HomeWidgetStore.shared else {
            widgetLog.error("App Group container unavailable — widget snapshot not written")
            return
        }
        let widgetVideos = HomeWidgetStore.widgetVideos(from: videos)
        saveTask?.cancel()
        guard !widgetVideos.isEmpty else {
            // Signed out: show the widget's empty state instead of a stale personal feed.
            guard store.load() != nil else { return }
            store.clear()
            widgetLog.notice("no Home videos (signed out) — snapshot cleared")
            WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetStore.widgetKind)
            return
        }
        saveTask = Task.detached(priority: .utility) {
            do {
                guard try await store.save(widgetVideos) else { return }
                widgetLog.notice("snapshot saved (\(widgetVideos.count) videos) — reloading widget")
                WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetStore.widgetKind)
            } catch {
                widgetLog.error("snapshot save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
