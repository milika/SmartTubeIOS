import Foundation

// MARK: - CurrentQueueStore
//
// Ordered list of videos the user has queued to play one after another.
// Surfaced in the Library as a synthetic "Current Queue" playlist.
//
// Thread-safe: implemented as a Swift actor — mirrors VideoStateStore and
// LocalSubscriptionStore.

public actor CurrentQueueStore: UserDefaultsBackedStore {

    // MARK: - Singleton

    public static let shared = CurrentQueueStore()

    // MARK: - Storage

    static let defaultsKey = "st_current_queue"
    private static let maxCount = 500

    /// The synthetic playlist ID used to tag queued videos. Declared `nonisolated`
    /// so it can be read from any actor context (e.g. @MainActor views) without `await`.
    public nonisolated static let playlistID = "__current_queue__"

    // MARK: - State

    public private(set) var videos: [Video] = []
    let defaults: UserDefaults

    // MARK: - Init

    private init() {
        self.defaults = .standard
        if let loaded = Self.loadFrom(.standard) { videos = loaded }
    }

    /// Designated initializer for unit tests.
    /// Pass a unique `suiteName` to get a fully isolated store with no shared
    /// UserDefaults state — mirrors VideoStateStore(suiteName:).
    init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let loaded = Self.loadFrom(self.defaults) { videos = loaded }
    }

    // MARK: - Public API

    /// Appends `video` to the end of the queue. No-op if the queue is at capacity or already contains the video.
    public func append(_ video: Video) {
        guard videos.count < Self.maxCount else { return }
        guard !videos.contains(where: { $0.id == video.id }) else { return }
        videos.append(video)
        persist()
    }

    /// Inserts `video` immediately after `afterIndex` so it plays next.
    /// Pass `-1` to insert at position 0. No-op if already in the queue.
    public func insertNext(_ video: Video, afterIndex: Int) {
        guard videos.count < Self.maxCount else { return }
        guard !videos.contains(where: { $0.id == video.id }) else { return }
        let insertAt = min(afterIndex + 1, videos.count)
        videos.insert(video, at: insertAt)
        persist()
    }

    /// Removes the video at `index`. Safe to call with an out-of-range index.
    public func remove(at index: Int) {
        guard videos.indices.contains(index) else { return }
        videos.remove(at: index)
        persist()
    }

    /// Moves a video — same semantics as `Array.move(fromOffsets:toOffset:)` used by SwiftUI List.
    public func move(from source: IndexSet, to destination: Int) {
        videos.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Empties the queue and removes the UserDefaults entry.
    public func clear() {
        videos = []
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Atomically replaces the queue with `newVideos`, preserving playlist order
    /// and allowing duplicate video IDs (a real playlist can contain the same video
    /// at two different positions). Caps at `maxCount`. Persists immediately.
    public func replaceAll(with newVideos: [Video]) {
        videos = Array(newVideos.prefix(Self.maxCount))
        persist()
    }

    // MARK: - Playlist adapter

    /// Returns the video at `index` tagged with the queue's synthetic `playlistId`
    /// and the correct `playlistIndex`. This is what the player receives.
    public func videoAt(index: Int) -> Video? {
        guard videos.indices.contains(index) else { return nil }
        var copy = videos[index]
        copy.playlistId = Self.playlistID
        copy.playlistIndex = index
        return copy
    }

    /// Returns all queue videos after `index`, each tagged with `playlistId` and `playlistIndex`.
    /// Used by shuffle logic in `PlaybackViewModel` to pick a random remaining video.
    public func remainingVideos(after index: Int) -> [Video] {
        let startIdx = index + 1
        guard startIdx < videos.count else { return [] }
        return (startIdx..<videos.count).map { i in
            var copy = videos[i]
            copy.playlistId = Self.playlistID
            copy.playlistIndex = i
            return copy
        }
    }

    /// A `PlaylistInfo` stub for rendering the queue row in LibraryView.
    public var asPlaylistInfo: PlaylistInfo {
        PlaylistInfo(
            id: Self.playlistID,
            title: L10n.string("Current Queue"),
            videoCount: videos.count,
            thumbnailURL: videos.first?.thumbnailURL
        )
    }

    // MARK: - UserDefaultsBackedStore

    func encodedValue() -> [Video] { videos }
    func decodeValue(_ decoded: [Video]) { videos = decoded }

    func afterPersist() {
        let value = videos
        Task { await iCloudSyncManager.shared.push(.currentQueue, value) }
    }
}
