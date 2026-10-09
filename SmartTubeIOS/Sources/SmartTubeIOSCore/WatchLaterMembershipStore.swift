import Foundation
import Observation

// MARK: - WatchLaterMembershipStore (#39)
//
// Tracks which video IDs this app has saved to (or removed from) the user's Watch
// Later playlist, so VideoCardView can show a "Saved" indicator on a video's card
// wherever it reappears (Home, Search, a channel page, etc.).
//
// IMPORTANT LIMITATION: YouTube's feed/browse responses do not include a per-video
// "is this in my Watch Later" flag, so there is no way to derive this from the API
// without fetching and diffing the entire Watch Later playlist on every card render
// (not practical for feed-sized lists). This store therefore only reflects videos
// added or removed via *this app*, persisted locally across launches — it will not
// know about videos saved from another SmartTube install, the official YouTube app,
// or youtube.com. That's a real gap, but it's still strictly more accurate than no
// indicator at all for the common case (the user saves videos from this app).
@Observable
@MainActor
public final class WatchLaterMembershipStore {
    public static let shared = WatchLaterMembershipStore()

    private static let defaultsKey = "com.smarttube.watchLaterMembership"

    public private(set) var videoIds: Set<String> = []

    /// When each video was saved *this session* — in-memory only. `videoIds` is persisted
    /// and never pruned, so it can't tell a just-saved video from one saved months ago (and
    /// since removed elsewhere); only recent saves justify waiting on YouTube's index (#157).
    private var savedAt: [String: Date] = [:]
    /// The videos saved this session (stamped with playlistId "WL" and, when YouTube returned
    /// it, their setVideoId), so the Watch Later list can show them before YouTube's index
    /// does — and remove them again (#157).
    private var savedVideos: [String: Video] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        videoIds = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    private let defaults: UserDefaults

    public func contains(_ videoId: String) -> Bool {
        videoIds.contains(videoId)
    }

    public func markSaved(_ videoId: String, at date: Date = Date()) {
        savedAt[videoId] = date
        guard videoIds.insert(videoId).inserted else { return }
        persist()
    }

    /// Records a save made from a video card, keeping the video so lists can show it.
    public func markSaved(_ video: Video, setVideoId: String?, at date: Date = Date()) {
        var saved = video
        saved.playlistId = "WL"
        if let setVideoId { saved.setVideoId = setVideoId }
        savedVideos[video.id] = saved
        markSaved(video.id, at: date)
        NotificationCenter.default.post(
            name: .watchLaterDidChange, object: nil, userInfo: ["videoId": video.id, "added": true])
    }

    public func markRemoved(_ videoId: String) {
        savedAt[videoId] = nil
        savedVideos[videoId] = nil
        NotificationCenter.default.post(
            name: .watchLaterDidChange, object: nil, userInfo: ["videoId": videoId, "added": false])
        guard videoIds.remove(videoId) != nil else { return }
        persist()
    }

    /// A video saved this session, as it should appear in the Watch Later list.
    public func savedVideo(_ videoId: String) -> Video? {
        savedVideos[videoId]
    }

    /// The playlist-entry token YouTube returned when this video was saved this session.
    public func setVideoId(for videoId: String) -> String? {
        savedVideos[videoId]?.setVideoId
    }

    /// Videos saved this session within `interval` seconds of `now`, newest first.
    public func recentlySavedVideos(within interval: TimeInterval, now: Date = Date()) -> [Video] {
        savedAt.filter { now.timeIntervalSince($0.value) <= interval }
            .sorted { $0.value > $1.value }
            .compactMap { savedVideos[$0.key] }
    }

    /// Videos saved via this app within the last `interval` seconds of `now`.
    public func recentlySaved(within interval: TimeInterval, now: Date = Date()) -> Set<String> {
        Set(savedAt.filter { now.timeIntervalSince($0.value) <= interval }.keys)
    }

    private func persist() {
        defaults.set(Array(videoIds), forKey: Self.defaultsKey)
    }
}
