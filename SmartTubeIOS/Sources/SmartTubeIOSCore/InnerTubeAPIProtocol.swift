import Foundation

// MARK: - InnerTubeAPIProtocol
//
// The dependency interface for all four feed ViewModels (Home, Browse, Search,
// Playlist).  Decouples ViewModels from the concrete InnerTubeAPI actor so
// they can be injected with a mock in unit tests.
//
// All methods are declared `async` (matching how ViewModels call them).
// A synchronous actor method satisfies an `async` protocol requirement in
// Swift — the actor's isolation guarantees safe concurrent access.

public protocol InnerTubeAPIProtocol: AnyObject, Sendable {

    // MARK: Auth
    func setAuthToken(_ token: String?) async
    func setSAPISID(_ value: String?) async

    // MARK: Home / browse
    func fetchHome(continuationToken: String?) async throws -> VideoGroup
    func fetchHomeRows(continuationToken: String?) async throws -> [VideoGroup]
    func fetchSubscriptions(continuationToken: String?) async throws -> VideoGroup
    func fetchHistory(continuationToken: String?) async throws -> VideoGroup
    func fetchShorts() async throws -> VideoGroup
    func fetchShortsMore(continuationToken: String) async throws -> VideoGroup
    func fetchMusic() async throws -> VideoGroup
    func fetchGaming() async throws -> VideoGroup
    func fetchNews() async throws -> VideoGroup
    func fetchLive() async throws -> VideoGroup
    func fetchSports() async throws -> VideoGroup

    // MARK: Library
    func fetchUserPlaylists() async throws -> [PlaylistInfo]
    func fetchSubscribedChannels() async throws -> [Channel]

    // MARK: Channel
    func fetchChannelThumbnailURL(channelId: String) async throws -> URL?
    func fetchChannel(channelId: String) async throws -> (channel: Channel, videos: VideoGroup)
    func fetchChannelVideos(channelId: String, continuationToken: String?) async throws -> VideoGroup

    // MARK: Search
    func search(query: String, continuationToken: String?, filter: SearchFilter) async throws -> VideoGroup
    func fetchSearchSuggestions(query: String) async throws -> [String]

    // MARK: Playlist
    func fetchPlaylistVideos(playlistId: String, continuationToken: String?) async throws -> VideoGroup

    // MARK: Playlist editing
    @discardableResult
    func addToWatchLater(videoId: String) async throws -> String?
    func removeFromWatchLater(setVideoId: String) async throws
    func addToPlaylist(playlistId: String, videoId: String) async throws
    func removeFromPlaylist(playlistId: String, setVideoId: String) async throws
    func sendFeedback(token: String) async throws
    /// On-demand feedback when no pre-fetched token is available (TV-client home feed).
    /// `iconType` is one of `"NOT_INTERESTED"`, `"DISLIKE"`, or `"BLOCK_CHANNEL"`.
    func sendFeedbackForVideo(videoId: String, iconType: String) async throws
}

// MARK: - Default-parameter convenience wrappers

public extension InnerTubeAPIProtocol {

    /// Fetches the flat recommended home feed from the first page.
    func fetchHome() async throws -> VideoGroup {
        try await fetchHome(continuationToken: nil)
    }

    /// Fetches the home-feed row shelves from the first page.
    func fetchHomeRows() async throws -> [VideoGroup] {
        try await fetchHomeRows(continuationToken: nil)
    }

    /// Fetches the subscriptions feed from the first page.
    func fetchSubscriptions() async throws -> VideoGroup {
        try await fetchSubscriptions(continuationToken: nil)
    }

    /// Fetches the watch history from the first page.
    func fetchHistory() async throws -> VideoGroup {
        try await fetchHistory(continuationToken: nil)
    }

    /// Searches using default filter and no continuation.
    func search(query: String) async throws -> VideoGroup {
        try await search(query: query, continuationToken: nil, filter: .default)
    }
}

// MARK: - InnerTubeAPI conformance

extension InnerTubeAPI: InnerTubeAPIProtocol {}
