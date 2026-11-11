import Foundation
import Observation
import os

private let feedLog = Logger(subsystem: appSubsystem, category: "ShortsFeed")

// MARK: - ShortsFeedProviding

/// The InnerTube calls the Shorts feed needs. `InnerTubeAPI` conforms; tests inject a fake.
public protocol ShortsFeedProviding: AnyObject, Sendable {
    func fetchShortsFeed(seedVideoId: String?) async throws -> ShortsFeedPage
    func fetchShortsFeedMore(continuation: String) async throws -> ShortsFeedPage
    func fetchShortMetadata(videoId: String) async throws -> ShortMetadata
    /// Last-resort fallback (`#shorts` search) when the reel endpoints fail.
    func searchShorts() async throws -> VideoGroup
    func fetchShortsMore(continuationToken: String) async throws -> VideoGroup
    func like(videoId: String) async throws
    func dislike(videoId: String) async throws
    func removeLike(videoId: String) async throws
    func subscribe(channelId: String) async throws
    func unsubscribe(channelId: String) async throws
}

extension InnerTubeAPI: ShortsFeedProviding {}

// MARK: - ShortsFeedViewModel

/// The list of Shorts the Shorts player pages through, fed by YouTube's own Shorts
/// sequence (personalised when signed in), plus per-Short overlay metadata and the
/// like/subscribe actions shown on the overlay.
@MainActor
@Observable
public final class ShortsFeedViewModel {

    public enum Source: Sendable {
        /// YouTube's sequence. `seed` (the tapped Short) is shown first and seeds the
        /// algorithm; nil starts a seedless feed (Shorts tab).
        case algorithm(seed: Video?)
        /// A fixed list (e.g. a channel's Shorts) that continues with YouTube's
        /// sequence, seeded from its last Short, once the user reaches the end.
        case list([Video], startIndex: Int)
    }

    /// How close to the end of `videos` the next page is requested.
    public static let prefetchDistance = 3

    public private(set) var videos: [Video]
    public let startIndex: Int
    /// True while the very first page of a seedless feed is loading (no video to show yet).
    public private(set) var isLoadingInitial = false
    public private(set) var isFetchingMore = false
    /// True when YouTube reported the sequence as signed in (`logged_in=1`).
    public private(set) var isPersonalized = false
    /// Set when the feed could not be loaded at all.
    public private(set) var loadError: String?
    public private(set) var metadata: [String: ShortMetadata] = [:]

    private let provider: any ShortsFeedProviding
    private let source: Source
    private var continuation: String?
    private var searchContinuation: String?
    private var usingSearchFallback = false
    private var exhausted = false
    private var didStart = false
    private var metadataInFlight: Set<String> = []
    private var hiddenChannelIds: Set<String> = []

    public init(source: Source, provider: any ShortsFeedProviding) {
        self.source = source
        self.provider = provider
        switch source {
        case .algorithm(let seed):
            videos = seed.map { [$0] } ?? []
            startIndex = 0
        case .list(let list, let start):
            videos = list
            startIndex = list.indices.contains(start) ? start : 0
        }
    }

    // MARK: Feed

    /// Loads the first algorithmic page. No-op for `.list` sources — they fetch
    /// lazily via `loadMoreIfNeeded(currentIndex:)` when the list runs out.
    public func start() async {
        guard case .algorithm(let seed) = source, !didStart else { return }
        didStart = true
        isLoadingInitial = videos.isEmpty
        defer { isLoadingInitial = false }
        await fetchFirstPage(seedVideoId: seed?.id)
    }

    /// Requests the next page when `currentIndex` is within `prefetchDistance` of the end.
    public func loadMoreIfNeeded(currentIndex: Int) async {
        guard currentIndex >= videos.count - Self.prefetchDistance, !isFetchingMore, !exhausted else { return }
        if let continuation {
            await fetchMore(continuation: continuation)
        } else if usingSearchFallback, let searchContinuation {
            await fetchMoreFromSearch(token: searchContinuation)
        } else if !usingSearchFallback {
            // `.list` source (or an algorithm feed whose first page failed): seed from the last Short.
            await fetchFirstPage(seedVideoId: videos.last?.id)
        } else {
            exhausted = true
        }
    }

    // MARK: Metadata

    /// Loads (once) the overlay metadata for `videoId` and copies title/channel into
    /// the matching `videos` entry so history and sharing see real titles.
    public func loadMetadata(for videoId: String, signedIn: Bool) async {
        guard metadata[videoId] == nil, metadataInFlight.insert(videoId).inserted else { return }
        defer { metadataInFlight.remove(videoId) }
        do {
            var fetched = try await provider.fetchShortMetadata(videoId: videoId)
            if !signedIn, let channelId = fetched.channelId {
                fetched.isSubscribed = await LocalSubscriptionStore.shared.isFollowing(channelId)
            }
            metadata[videoId] = fetched
            if let index = videos.firstIndex(where: { $0.id == videoId }) {
                if videos[index].title.isEmpty { videos[index].title = fetched.title }
                if videos[index].channelTitle.isEmpty { videos[index].channelTitle = fetched.channelTitle }
                if videos[index].channelId == nil { videos[index].channelId = fetched.channelId }
            }
        } catch {
            feedLog.notice(
                "metadata failed for \(videoId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Actions

    /// Like ↔ none. Optimistic; reverts on failure. Requires sign-in (caller gates).
    public func toggleLike(videoId: String) async {
        await setLikeStatus(videoId: videoId, to: metadata[videoId]?.likeStatus == .like ? .none : .like)
    }

    /// Dislike ↔ none. Optimistic; reverts on failure. Requires sign-in (caller gates).
    public func toggleDislike(videoId: String) async {
        await setLikeStatus(videoId: videoId, to: metadata[videoId]?.likeStatus == .dislike ? .none : .dislike)
    }

    /// Subscribes/unsubscribes the channel of `videoId`. Signed in → YouTube account;
    /// signed out → the app's local subscriptions (same as ChannelView).
    public func toggleSubscription(videoId: String, signedIn: Bool) async {
        guard let current = metadata[videoId], let channelId = current.channelId else { return }
        let subscribe = !current.isSubscribed
        updateSubscription(channelId: channelId, to: subscribe)
        do {
            if signedIn {
                if subscribe {
                    try await provider.subscribe(channelId: channelId)
                } else {
                    try await provider.unsubscribe(channelId: channelId)
                }
            } else if subscribe {
                let local = LocalChannel(
                    id: channelId, title: current.channelTitle, thumbnailURL: current.channelAvatarURL)
                await LocalSubscriptionStore.shared.follow(local)
            } else {
                await LocalSubscriptionStore.shared.unfollow(channelId: channelId)
            }
        } catch {
            feedLog.error("subscription change failed: \(String(describing: error), privacy: .public)")
            updateSubscription(channelId: channelId, to: !subscribe)
        }
    }

    /// "Don't recommend channel": drops the Shorts after `index` that come from
    /// `channelId`, and keeps later pages from adding more of them. Shorts at or
    /// before `index` stay so the current position doesn't move.
    public func hideChannel(_ channelId: String, after index: Int) {
        hiddenChannelIds.insert(channelId)
        removeHiddenChannels(after: index)
    }

    /// Drops the Shorts after `index` whose channel is hidden. Reel entries arrive
    /// without a channel, so a page can slip a hidden channel's Short past `append`;
    /// call this once metadata has identified more channels.
    public func removeHiddenChannels(after index: Int) {
        guard !hiddenChannelIds.isEmpty else { return }
        var position = 0
        videos.removeAll { video in
            defer { position += 1 }
            guard position > index, let channelId = self.channelId(of: video) else { return false }
            return hiddenChannelIds.contains(channelId)
        }
    }

    private func channelId(of video: Video) -> String? {
        video.channelId ?? metadata[video.id]?.channelId
    }

    // MARK: Private

    private func fetchFirstPage(seedVideoId: String?) async {
        isFetchingMore = true
        defer { isFetchingMore = false }
        do {
            let page = try await provider.fetchShortsFeed(seedVideoId: seedVideoId)
            apply(page)
        } catch {
            feedLog.error(
                "Shorts sequence failed (\(String(describing: error), privacy: .public)) — falling back to #shorts search"
            )
            await startSearchFallback()
        }
    }

    private func fetchMore(continuation token: String) async {
        isFetchingMore = true
        defer { isFetchingMore = false }
        do {
            apply(try await provider.fetchShortsFeedMore(continuation: token))
        } catch {
            feedLog.error("Shorts continuation failed: \(String(describing: error), privacy: .public)")
            continuation = nil
            await startSearchFallback()
        }
    }

    private func apply(_ page: ShortsFeedPage) {
        isPersonalized = page.isPersonalized
        continuation = page.continuation
        exhausted = page.continuation == nil
        append(page.videos)
        loadError = nil
    }

    private func startSearchFallback() async {
        guard !usingSearchFallback else {
            exhausted = true
            return
        }
        usingSearchFallback = true
        do {
            let group = try await provider.searchShorts()
            searchContinuation = group.nextPageToken
            append(group.videos)
            if group.nextPageToken == nil { exhausted = true }
        } catch {
            exhausted = true
            if videos.isEmpty { loadError = String(describing: error) }
        }
    }

    private func fetchMoreFromSearch(token: String) async {
        isFetchingMore = true
        defer { isFetchingMore = false }
        do {
            let group = try await provider.fetchShortsMore(continuationToken: token)
            searchContinuation = group.nextPageToken
            append(group.videos)
            if group.nextPageToken == nil { exhausted = true }
        } catch {
            exhausted = true
        }
    }

    /// Appends Shorts not already in `videos`; returns how many were added.
    @discardableResult
    private func append(_ newVideos: [Video]) -> Int {
        var seen = Set(videos.map(\.id))
        let fresh = newVideos.filter { video in
            if let channelId = video.channelId, hiddenChannelIds.contains(channelId) { return false }
            return seen.insert(video.id).inserted
        }
        videos.append(contentsOf: fresh)
        return fresh.count
    }

    private func setLikeStatus(videoId: String, to newStatus: LikeStatus) async {
        guard let previous = metadata[videoId]?.likeStatus, previous != newStatus else { return }
        metadata[videoId]?.likeStatus = newStatus
        do {
            switch newStatus {
            case .like: try await provider.like(videoId: videoId)
            case .dislike: try await provider.dislike(videoId: videoId)
            case .none: try await provider.removeLike(videoId: videoId)
            }
        } catch {
            feedLog.error("like change failed: \(String(describing: error), privacy: .public)")
            metadata[videoId]?.likeStatus = previous
        }
    }

    /// Every Short from the same channel shares the subscribe state.
    private func updateSubscription(channelId: String, to subscribed: Bool) {
        for (id, item) in metadata where item.channelId == channelId {
            metadata[id]?.isSubscribed = subscribed
        }
    }
}
