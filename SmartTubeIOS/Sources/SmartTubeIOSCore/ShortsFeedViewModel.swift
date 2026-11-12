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
    /// How many pages in a row one fetch follows while they add nothing (all
    /// duplicates or hidden channels). An unchanged count would otherwise leave an
    /// auto-scroll waiting at the end with nothing to trigger the next request.
    static let maxPagesPerFetch = 5
    /// `loadError` when YouTube answered but had no Shorts at all.
    static let emptyFeedMessage = "YouTube returned no Shorts."

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

    /// Loads the first algorithmic page; again if nothing could be loaded last time
    /// (e.g. offline), so returning to the feed retries. No-op for `.list` sources —
    /// they fetch lazily via `loadMoreIfNeeded(currentIndex:)` when the list runs out.
    public func start() async {
        guard case .algorithm(let seed) = source, !isFetchingMore else { return }
        guard !didStart || (videos.isEmpty && loadError != nil) else { return }
        didStart = true
        loadError = nil
        isLoadingInitial = videos.isEmpty
        defer { isLoadingInitial = false }
        await fetchFirstPage(seedVideoId: seed?.id)
    }

    /// Requests the next page when `currentIndex` is within `prefetchDistance` of the end.
    /// An empty feed that failed to load retries through `start()` instead.
    public func loadMoreIfNeeded(currentIndex: Int) async {
        guard currentIndex >= videos.count - Self.prefetchDistance, !isFetchingMore, !exhausted,
            loadError == nil
        else { return }
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
            if apply(page) == 0, let next = page.continuation { await followSequence(from: next) }
        } catch {
            feedLog.error(
                "Shorts sequence failed (\(String(describing: error), privacy: .public)) — falling back to #shorts search"
            )
            await startSearchFallback()
        }
        await fallBackIfEmpty()
    }

    /// The sequence (or the search) ran out without a single Short. Tries the search
    /// if it hasn't run yet; if that has none either, reports the feed as failed, so
    /// the empty state says so and the next `start()` retries instead of showing a
    /// spinner that never ends.
    private func fallBackIfEmpty() async {
        guard videos.isEmpty, exhausted, loadError == nil else { return }
        if !usingSearchFallback {
            feedLog.error("Shorts sequence came back empty — falling back to #shorts search")
            await startSearchFallback()
            guard videos.isEmpty, exhausted, loadError == nil else { return }
        }
        feedLog.error("Shorts feed came back empty")
        resetPaging()
        loadError = Self.emptyFeedMessage
    }

    private func fetchMore(continuation token: String) async {
        isFetchingMore = true
        defer { isFetchingMore = false }
        await followSequence(from: token)
    }

    /// Fetches sequence pages from `token` until one adds a Short (see `maxPagesPerFetch`).
    private func followSequence(from token: String) async {
        var token = token
        for _ in 0..<Self.maxPagesPerFetch {
            do {
                let page = try await provider.fetchShortsFeedMore(continuation: token)
                guard apply(page) == 0, let next = page.continuation else { return }
                token = next
            } catch {
                feedLog.error("Shorts continuation failed: \(String(describing: error), privacy: .public)")
                continuation = nil
                await startSearchFallback()
                return
            }
        }
    }

    /// Returns how many Shorts the page added.
    private func apply(_ page: ShortsFeedPage) -> Int {
        isPersonalized = page.isPersonalized
        continuation = page.continuation
        exhausted = page.continuation == nil
        loadError = nil
        return append(page.videos)
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
            let added = append(group.videos)
            if let next = group.nextPageToken {
                if added == 0 { await followSearch(from: next) }
            } else {
                exhausted = true
            }
        } catch {
            failed(error)
        }
    }

    private func fetchMoreFromSearch(token: String) async {
        isFetchingMore = true
        defer { isFetchingMore = false }
        await followSearch(from: token)
    }

    /// Fetches search pages from `token` until one adds a Short (see `maxPagesPerFetch`).
    private func followSearch(from token: String) async {
        var token = token
        for _ in 0..<Self.maxPagesPerFetch {
            do {
                let group = try await provider.fetchShortsMore(continuationToken: token)
                searchContinuation = group.nextPageToken
                let added = append(group.videos)
                guard let next = group.nextPageToken else {
                    exhausted = true
                    return
                }
                guard added == 0 else { return }
                token = next
            } catch {
                failed(error)
                return
            }
        }
    }

    /// The sequence and the search fallback both failed (usually offline). Forgets
    /// the paging state instead of marking the feed exhausted, so the next
    /// `start()` / `loadMoreIfNeeded(currentIndex:)` retries from the sequence.
    private func failed(_ error: Error) {
        feedLog.error("Shorts feed failed: \(String(describing: error), privacy: .public)")
        resetPaging()
        if videos.isEmpty { loadError = String(describing: error) }
    }

    private func resetPaging() {
        continuation = nil
        searchContinuation = nil
        usingSearchFallback = false
        exhausted = false
    }

    /// Appends Shorts not already in `videos` and not from a hidden channel; returns
    /// how many were added. Reel entries carry no channel, so the channel comes from
    /// cached metadata when an earlier page's copy of the Short was identified.
    @discardableResult
    private func append(_ newVideos: [Video]) -> Int {
        var seen = Set(videos.map(\.id))
        let fresh = newVideos.filter { video in
            if let channelId = channelId(of: video), hiddenChannelIds.contains(channelId) { return false }
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
