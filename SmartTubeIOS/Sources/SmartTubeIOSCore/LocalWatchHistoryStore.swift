import Foundation
import Observation

// MARK: - LocalWatchHistoryStore (#150, task #346)
//
// SmartTube's sign-in (Google device-code flow) yields no YouTube *web* session cookies,
// so playback pings are not credited to the account's real YouTube history (see open task
// #293 for the rejected/alternative designs). Rather than pretend otherwise, the app keeps
// its own on-device history: every video that starts playing (outside Incognito, with
// Watch History enabled) is recorded here and shown at the top of the History tab.
// Nothing here talks to YouTube.

public struct LocalWatchHistoryEntry: Codable, Equatable, Sendable {
    public let video: Video
    public let watchedAt: Date

    public init(video: Video, watchedAt: Date) {
        self.video = video
        self.watchedAt = watchedAt
    }
}

@Observable
@MainActor
public final class LocalWatchHistoryStore {
    public static let shared = LocalWatchHistoryStore()

    public static let maxEntries = 300
    private static let defaultsKey = "com.smarttube.localWatchHistory"

    /// Most recent first, unique by video id.
    public private(set) var entries: [LocalWatchHistoryEntry] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([LocalWatchHistoryEntry].self, from: data)
        {
            entries = decoded
        }
    }

    /// Records `video` as watched now, moving it to the front if already present and
    /// evicting the oldest entries beyond `maxEntries`. Only identity/display fields are
    /// kept — per-fetch state like tracking tokens is dropped so stale tokens are never
    /// replayed from disk.
    public func record(_ video: Video, at date: Date = Date()) {
        let slim = Video(
            id: video.id, title: video.title, channelTitle: video.channelTitle,
            channelId: video.channelId, thumbnailURL: video.thumbnailURL,
            duration: video.duration, isLive: video.isLive, isShort: video.isShort)
        entries.removeAll { $0.video.id == video.id }
        entries.insert(LocalWatchHistoryEntry(video: slim, watchedAt: date), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        persist()
    }

    public func clear() {
        entries = []
        persist()
    }

    /// Videos in the History tab's shape: local entries first (newest first).
    public var videos: [Video] { entries.map(\.video) }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
