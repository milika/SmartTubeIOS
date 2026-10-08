#if os(iOS)
import CoreSpotlight
import Foundation
import SmartTubeIOSCore
import UniformTypeIdentifiers
import os

private let spotlightLog = Logger(subsystem: "com.void.smarttube.app", category: "Spotlight")

// MARK: - SpotlightIndexer
//
// Puts recently watched videos and subscribed channels into system search (Spotlight).
// Tapping a result opens the app with a CSSearchableItemActionType user activity whose
// identifier ("video:ID" / "channel:ID") maps to a SmartTubeRoute.
//
// Indexing is incremental: the ids already indexed are remembered, so a launch only adds
// what is new (and downloads only those thumbnails) and removes what dropped out.

@MainActor
public final class SpotlightIndexer {
    public static let shared = SpotlightIndexer()

    static let historyDomain = "com.void.smarttube.history"
    static let channelsDomain = "com.void.smarttube.channels"
    static let maxHistoryItems = 50
    static let maxChannelItems = 300

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Routing

    /// The route for a tapped Spotlight result, from its unique identifier.
    public nonisolated static func route(forIdentifier identifier: String) -> SmartTubeRoute? {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "video": return .video(id: parts[1])
        case "channel": return .channel(id: parts[1])
        default: return nil
        }
    }

    // MARK: Sync

    /// Keeps the newest `maxHistoryItems` watched videos indexed. Empty clears them all
    /// (history cleared or turned off).
    public func syncHistory(_ videos: [Video]) {
        let top = Array(videos.filter { !$0.isShort }.prefix(Self.maxHistoryItems))
        sync(
            domain: Self.historyDomain, key: "spotlight.indexedHistory",
            items: top.map { video in
                Item(
                    id: "video:\(video.id)", title: video.title, detail: video.channelTitle,
                    thumbnail: video.thumbnailURL, keywords: [video.channelTitle])
            })
    }

    /// Keeps the subscribed channels indexed. Pass an empty list on sign-out.
    public func syncChannels(_ channels: [Channel]) {
        sync(
            domain: Self.channelsDomain, key: "spotlight.indexedChannels",
            items: channels.prefix(Self.maxChannelItems).map { channel in
                Item(
                    id: "channel:\(channel.id)", title: channel.title,
                    detail: String(localized: "YouTube channel", bundle: .module), thumbnail: channel.thumbnailURL,
                    keywords: ["channel"])
            })
    }

    private struct Item: Sendable {
        let id: String
        let title: String
        let detail: String
        let thumbnail: URL?
        let keywords: [String]
    }

    private func sync(domain: String, key: String, items: [Item]) {
        let indexed = Set(defaults.stringArray(forKey: key) ?? [])
        let wanted = Set(items.map(\.id))
        let removed = Array(indexed.subtracting(wanted))
        let added = items.filter { !indexed.contains($0.id) }
        guard !removed.isEmpty || !added.isEmpty else { return }
        defaults.set(Array(wanted), forKey: key)

        Task.detached(priority: .utility) {
            // CSSearchableIndex isn't Sendable, so the task takes its own reference.
            let index = CSSearchableIndex.default()
            if !removed.isEmpty {
                try? await index.deleteSearchableItems(withIdentifiers: removed)
            }
            guard !added.isEmpty else { return }
            var searchable: [CSSearchableItem] = []
            for item in added {
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = item.title
                attributes.contentDescription = item.detail
                attributes.keywords = item.keywords + ["SmartTube", "YouTube"]
                if let url = item.thumbnail,
                    let (data, _) = try? await URLSession.shared.data(from: url),
                    let jpeg = HomeWidgetStore.downscaledJPEG(data, maxWidth: 240)
                {
                    attributes.thumbnailData = jpeg
                }
                searchable.append(
                    CSSearchableItem(uniqueIdentifier: item.id, domainIdentifier: domain, attributeSet: attributes))
            }
            do {
                try await index.indexSearchableItems(searchable)
                spotlightLog.notice("\(domain, privacy: .public): +\(added.count) −\(removed.count)")
            } catch {
                spotlightLog.error("indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
