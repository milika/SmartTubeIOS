import Foundation
import Observation
import os

private let homeLog = ViewModelLogger(category: "Home")

// MARK: - HomeViewModel
//
// Fetches Subscriptions and Recommended shelves in parallel
// to populate the Home tab's multi-section feed.

@MainActor
@Observable
public final class HomeViewModel {

    // MARK: - Section state

    public struct SectionState: Identifiable {
        public let section: BrowseSection
        public var videos: [Video] = []
        public var isLoading: Bool = true
        public var isLoadingMore: Bool = false
        public var hasFailed: Bool = false
        public var nextPageToken: String? = nil
        public var id: String { section.id }
    }

    // MARK: - State

    public private(set) var sections: [SectionState]
    /// The Shorts shelf: YouTube's Shorts algorithm (`fetchShorts()`), personalised
    /// when signed in.
    public private(set) var shortsVideos: [Video] = []
    /// `false` until `fetchShorts()` has answered for the current load. Until then the
    /// row stays empty: showing the subscription/Recommended-feed Shorts first made
    /// non-algorithm Shorts flash before the shelf replaced them.
    public private(set) var hasLoadedShortsShelf = false
    /// Continuation token from the last FEshorts fetch; used by loadMoreShortsIfNeeded.
    private var shortsNextPageToken: String? = nil
    private var isLoadingMoreShorts: Bool = false
    /// Background cascade started after `load()` finishes; keeps paging Shorts
    /// content toward `preloadMoreShorts`'s threshold. Cancelled on the next `load()`.
    private var shortsPreloadTask: Task<Void, Never>? = nil
    public private(set) var isRefreshing: Bool = false
    /// Timestamp of the last successful load. Used for staleness checks.
    public private(set) var loadedAt: Date? = nil
    /// Frozen snapshot of the interleaved home feed. Updated once both sections
    /// finish loading (avoiding mid-load rearrangement). Appended to during
    /// pagination without ever reordering existing items.
    public private(set) var mergedVideos: [Video] = []

    // MARK: - Shelf definitions (in display order)

    public static let shelfSections: [BrowseSection] = [
        BrowseSection(id: BrowseSection.SectionType.home.rawValue, title: "Recommended", type: .home),
        BrowseSection(
            id: BrowseSection.SectionType.subscriptions.rawValue, title: "Subscriptions", type: .subscriptions),
    ]

    /// Number of recommended videos inserted between each subscription video
    /// in the interleaved home feed.
    private static let interleaveRatio = 4

    /// `true` while either the recommended or subscriptions section is still on
    /// its initial load (no videos yet).  Used by the view to show a spinner.
    public var isLoadingAny: Bool {
        sections.contains { $0.isLoading }
    }

    /// Rebuilds `mergedVideos` from both sections' current video lists.
    /// Called once after a full load completes so mid-load arrivals never
    /// rearrange already-rendered cards.  Not called during pagination —
    /// `loadMore` appends to `mergedVideos` directly to keep positions stable.
    private func rebuildMergedVideos() {
        let recState = sections.first { $0.section.type == .home }
        let subState = sections.first { $0.section.type == .subscriptions }
        let recs = recState?.videos ?? []
        let subs = subState?.videos ?? []

        guard !subs.isEmpty else {
            var seen = Set<String>()
            let deduped = recs.filter { seen.insert($0.id).inserted }
            if deduped.count != recs.count {
                homeLog.notice(
                    "rebuildMergedVideos: recs-only dedup removed \(recs.count - deduped.count) duplicate(s) (raw=\(recs.count))"
                )
            }
            mergedVideos = deduped
            return
        }
        guard !recs.isEmpty else {
            var seen = Set<String>()
            let deduped = subs.filter { seen.insert($0.id).inserted }
            if deduped.count != subs.count {
                homeLog.notice(
                    "rebuildMergedVideos: subs-only dedup removed \(subs.count - deduped.count) duplicate(s) (raw=\(subs.count))"
                )
            }
            mergedVideos = deduped
            return
        }

        let recIds = Set(recs.map(\.id))
        let uniqueSubs = subs.filter { !recIds.contains($0.id) }

        var result: [Video] = []
        result.reserveCapacity(recs.count + uniqueSubs.count)

        var subIndex = 0
        for (i, rec) in recs.enumerated() {
            result.append(rec)
            let slot = i + 1
            if slot % Self.interleaveRatio == 0, subIndex < uniqueSubs.count {
                result.append(uniqueSubs[subIndex])
                subIndex += 1
            }
        }
        if subIndex < uniqueSubs.count {
            result.append(contentsOf: uniqueSubs[subIndex...])
        }
        // Final safety-net dedup: prevents any remaining duplicate IDs from
        // reaching ForEach, which would cause SwiftUI to render blank cells.
        var seen = Set<String>()
        let deduped = result.filter { seen.insert($0.id).inserted }
        if deduped.count != result.count {
            homeLog.notice(
                "rebuildMergedVideos: final dedup removed \(result.count - deduped.count) duplicate(s) (subs+recs raw=\(result.count))"
            )
        }
        mergedVideos = deduped
    }

    /// Non-Short videos from the interleaved home feed.
    /// Used by `homeShelves` to populate the main grid (Shorts are shown separately).
    public var homeRegularVideos: [Video] { mergedVideos.filter { !$0.isShort } }

    /// Short videos for the dedicated Shorts row: the algorithm shelf only, like the
    /// official app. Only when the shelf (and its `#shorts` search fallback) came
    /// back empty does the row fall back to the Shorts found in the Subscriptions
    /// and Recommended feeds.
    public var homeShortsVideos: [Video] {
        guard hasLoadedShortsShelf else { return [] }
        guard usesFeedShortsFallback else { return shortsVideos }
        let subsShorts = sections.first { $0.section.type == .subscriptions }?.videos.filter { $0.isShort } ?? []
        var seen = Set<String>()
        return (subsShorts + mergedVideos.filter { $0.isShort })
            .filter { seen.insert($0.id).inserted }
    }

    /// The shelf answered with nothing, so the row shows feed Shorts instead.
    private var usesFeedShortsFallback: Bool { hasLoadedShortsShelf && shortsVideos.isEmpty }

    /// Continuation for paging the Subscriptions feed for more Shorts — only while
    /// the row is in its feed fallback; the shelf's own Shorts never come from there.
    private var subsShortsToken: String? {
        guard usesFeedShortsFallback else { return nil }
        return sections.first { $0.section.type == .subscriptions }?.nextPageToken
    }

    // MARK: - Dependencies

    private let api: any InnerTubeAPIProtocol
    private var loadTask: Task<Void, Never>?
    private var hideObserverTasks: [Task<Void, Never>] = []
    /// Tracks whether a non-nil auth token has been set. Used to distinguish a
    /// sign-in event (nil → non-nil) from a token refresh (non-nil → new non-nil)
    /// so that token refreshes during video playback do not trigger a feed reload.
    private var hasAuthToken: Bool = false

    public init(api: any InnerTubeAPIProtocol = InnerTubeAPI()) {
        self.api = api
        self.sections = Self.shelfSections.map { SectionState(section: $0) }
        observeFeedHideNotifications()
    }

    // MARK: - Feed hide handling

    private func observeFeedHideNotifications() {
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideVideoFromFeed) {
                    guard let self, let videoId = note.userInfo?["videoId"] as? String else { continue }
                    self.removeVideo(id: videoId)
                }
            })
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideChannelFromFeed) {
                    guard let self, let channelId = note.userInfo?["channelId"] as? String else { continue }
                    self.removeChannel(id: channelId)
                }
            })
        hideObserverTasks.append(
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .activeChannelDidChange) {
                    guard let self, self.hasAuthToken else { continue }
                    self.load()
                }
            })
    }

    public func removeVideo(id: String) {
        for i in sections.indices {
            sections[i].videos.removeAll { $0.id == id }
        }
        mergedVideos.removeAll { $0.id == id }
    }

    public func removeChannel(id: String) {
        for i in sections.indices {
            sections[i].videos.removeAll { $0.channelId == id }
        }
        mergedVideos.removeAll { $0.channelId == id }
    }

    /// Cancels all in-flight and background work (the main load task, the
    /// Shorts preload loop, and the feed-hide notification observers). Callers
    /// that create short-lived `HomeViewModel` instances — e.g. tests — should
    /// call this when done to avoid orphaned tasks bleeding state into later use.
    public func cancel() {
        loadTask?.cancel()
        shortsPreloadTask?.cancel()
        hideObserverTasks.forEach { $0.cancel() }
    }

    // MARK: - Public API

    public func load() {
        loadTask?.cancel()
        shortsPreloadTask?.cancel()
        loadedAt = nil
        isRefreshing = true
        shortsVideos = []
        shortsNextPageToken = nil
        hasLoadedShortsShelf = false
        mergedVideos = []
        for i in sections.indices {
            sections[i].videos = []
            sections[i].isLoading = true
            sections[i].isLoadingMore = false
            sections[i].hasFailed = false
            sections[i].nextPageToken = nil
        }

        loadTask = Task {
            // The Shorts shelf loads in parallel with the home/subs feed and shows as
            // soon as it arrives, independent of the feed sections.
            async let shortsShelfLoaded: Void = self.loadShortsShelf()

            await withTaskGroup(of: (String, [Video], String?).self) { group in
                for state in sections {
                    let sectionId = state.id
                    let type = state.section.type
                    let api = self.api
                    group.addTask {
                        let (videos, token) = await HomeViewModel.fetchVideos(type: type, api: api)
                        return (sectionId, videos, token)
                    }
                }
                for await (sectionId, videos, token) in group {
                    guard !Task.isCancelled else { break }
                    if let idx = sections.firstIndex(where: { $0.id == sectionId }) {
                        sections[idx].videos = videos
                        sections[idx].nextPageToken = token
                        sections[idx].isLoading = false
                        sections[idx].hasFailed = videos.isEmpty
                        // Show the first-arrived section immediately as a flat list so
                        // the user sees content right away.  We do NOT interleave here —
                        // that avoids re-ordering cards when the second section arrives.
                        if mergedVideos.isEmpty, !videos.isEmpty {
                            mergedVideos = videos
                        }
                    }
                }
            }
            // Both sections are now loaded. Rebuild the full interleaved list once,
            // replacing the partial first-arrived list. This is a single atomic swap
            // rather than incremental insertions, so existing card positions don't jump.
            rebuildMergedVideos()
            await shortsShelfLoaded
            guard !Task.isCancelled else { return }
            isRefreshing = false
            loadedAt = Date()
            let merged = self.mergedVideos
            let mergedShorts = merged.filter { $0.isShort }.count
            homeLog.notice(
                "load complete: merged=\(merged.count) regular=\(merged.count - mergedShorts) mergedShorts=\(mergedShorts) shortsSection=\(shortsVideos.count)"
            )
            // Keep paging Shorts content in the background toward preloadMoreShorts's
            // higher threshold, without delaying the load completion above.
            shortsPreloadTask = Task { @MainActor [weak self] in
                await self?.preloadMoreShorts()
            }
        }
    }

    /// Fetches the Shorts shelf and publishes it in one step, then fills it to the
    /// initial threshold (6 iOS / 8 tvOS). Further pages load as the user scrolls.
    private func loadShortsShelf() async {
        let (videos, token) = await Self.fetchShortsVideos(api: api)
        guard !Task.isCancelled else { return }
        shortsVideos = videos
        shortsNextPageToken = token
        hasLoadedShortsShelf = true
        await loadMoreShortsIfNeeded()
    }

    public func updateAuthToken(_ token: String?) async {
        let wasAuthenticated = hasAuthToken
        hasAuthToken = token != nil
        await api.setAuthToken(token)
        if token != nil && !wasAuthenticated {
            // Only reload on sign-in (nil → token). Token refreshes that happen
            // during video playback keep the same sign-in state and must not
            // wipe and reload the home feed.
            load()
        }
    }

    /// Refreshes both shelves if the last successful load was more than
    /// `threshold` seconds ago (default 15 min). No-op while loading.
    public func refreshIfStale(threshold: TimeInterval = 15 * 60) {
        guard !isRefreshing else { return }
        let age = loadedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age > threshold else { return }
        let ageDesc = age.isFinite ? "\(Int(age))s" : "never loaded"
        homeLog.notice("refreshIfStale: age=\(ageDesc) — reloading shelves")
        load()
    }

    // MARK: - Pagination

    public func loadMore(sectionId: String) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionId }),
            let token = sections[idx].nextPageToken,
            !sections[idx].isLoadingMore,
            !sections[idx].isLoading
        else { return }
        sections[idx].isLoadingMore = true
        let type = sections[idx].section.type
        Task {
            let (newVideos, nextToken) = await HomeViewModel.fetchMoreVideos(type: type, token: token, api: api)
            if let idx = sections.firstIndex(where: { $0.id == sectionId }) {
                // Use a growing set so IDs that appear multiple times within
                // newVideos itself (same page returning the same video twice)
                // are also caught — not just duplicates against existing videos.
                var seenIds = Set(sections[idx].videos.map(\.id))
                let deduplicated = newVideos.filter { seenIds.insert($0.id).inserted }
                sections[idx].videos.append(contentsOf: deduplicated)
                // NOTE: Do NOT sort after appending. The YouTube subscription feed API
                // returns pages in reverse-chronological order — page N+1 videos are
                // always older than page N. Sorting the entire array after each append
                // reorders existing items in SwiftUI's ForEach / mergedVideos interleave,
                // which breaks the LazyVGrid scroll position (content shifts under the
                // user's offset, making previously-seen cards reappear and the list
                // appear to jump back).
                //
                // Stable-append to mergedVideos: only add videos not already present,
                // preserving all existing card positions.
                let existingMergedIds = Set(mergedVideos.map(\.id))
                let newForMerged = deduplicated.filter { !existingMergedIds.contains($0.id) }
                mergedVideos.append(contentsOf: newForMerged)
                sections[idx].nextPageToken = nextToken
                sections[idx].isLoadingMore = false
            }
        }
    }

    /// Called by the merged home feed when the user scrolls near the bottom.
    /// Pages both the recommended and subscriptions sections simultaneously so
    /// the interleaved list keeps growing evenly.
    public func loadMoreMerged() {
        for state in sections where state.section.type == .home || state.section.type == .subscriptions {
            loadMore(sectionId: state.id)
        }
    }

    /// Called by the view when the user scrolls to the last card in the Shorts row.
    /// Loads the next page unconditionally — no minimum-count threshold — so the row
    /// grows on demand as the user scrolls past the already-loaded cards.
    public func loadNextShortsPage() {
        let subsToken = subsShortsToken
        homeLog.notice(
            "loadNextShortsPage: called — count=\(shortsVideos.count) isLoading=\(isLoadingMoreShorts) searchToken=\(shortsNextPageToken != nil) subsToken=\(subsToken != nil)"
        )
        guard !isLoadingMoreShorts, shortsNextPageToken != nil || subsToken != nil else {
            homeLog.notice("loadNextShortsPage: skipped — no tokens available")
            return
        }
        Task { @MainActor [weak self] in
            await self?.fetchAndAppendNextShortsPage()
        }
    }

    private func fetchAndAppendNextShortsPage() async {
        guard !isLoadingMoreShorts, shortsNextPageToken != nil || subsShortsToken != nil else { return }
        isLoadingMoreShorts = true
        defer { isLoadingMoreShorts = false }
        _ = await fetchOneShortsPage()
    }

    /// Fetches one increment of Shorts content: the shelf's next page if available.
    /// In the feed fallback (empty shelf) it pages the Subscriptions feed instead,
    /// whose Shorts `homeShortsVideos` then shows.
    /// Returns `true` if any new videos were appended.
    private func fetchOneShortsPage() async -> Bool {
        // Phase 1: one shelf page (reel: or srch: token from fetchShorts).
        if let token = shortsNextPageToken {
            homeLog.notice("fetchOneShortsPage search: fetching token=\(String(token.prefix(16)))\u{2026}")
            do {
                let more = try await api.fetchShortsMore(continuationToken: token)
                let existingIDs = Set(shortsVideos.map(\.id))
                let newVideos = more.videos.filter { !existingIDs.contains($0.id) }
                shortsVideos.append(contentsOf: newVideos)
                shortsNextPageToken = more.nextPageToken
                homeLog.notice(
                    "fetchOneShortsPage search: added \(newVideos.count) total=\(shortsVideos.count) hasMore=\(more.nextPageToken != nil)"
                )
                if !newVideos.isEmpty {
                    return true
                }
                // Search page returned 0 new Shorts — fall through to Phase 2
            } catch {
                homeLog.error("fetchOneShortsPage search: failed: \(error.localizedDescription)")
                shortsNextPageToken = nil
            }
        }
        // Phase 2: one subs page, only in the feed fallback.
        if let token = subsShortsToken,
            let idx = sections.firstIndex(where: { $0.section.type == .subscriptions })
        {
            homeLog.notice("fetchOneShortsPage subs: fetching token=\(String(token.prefix(16)))\u{2026}")
            let more = await Self.fetchMoreVideos(type: .subscriptions, token: token, api: api)
            let existingIDs = Set(sections[idx].videos.map(\.id))
            let newVideos = more.0.filter { !existingIDs.contains($0.id) }
            sections[idx].videos.append(contentsOf: newVideos)
            sections[idx].nextPageToken = more.1
            let newShorts = newVideos.filter { $0.isShort }.count
            homeLog.notice(
                "fetchOneShortsPage subs: added \(newVideos.count) (\(newShorts) shorts) hasMore=\(more.1 != nil)")
            return !newVideos.isEmpty
        }
        return false
    }

    /// Auto-loads an additional page of FEshorts if the current count falls below
    /// the threshold needed to fill 2 horizontal screens.
    /// iOS: ~3 cards/screen → threshold = 6; tvOS: ~4 cards/screen → threshold = 8.
    func loadMoreShortsIfNeeded() async {
        #if os(tvOS)
        let threshold = 8
        #else
        let threshold = 6
        #endif
        guard !isLoadingMoreShorts else {
            homeLog.notice("loadMoreShortsIfNeeded: skipped — already loading")
            return
        }
        guard shortsVideos.count < threshold, shortsNextPageToken != nil else {
            // If search token is exhausted but subs has a continuation, Phase 2 of
            // fetchOneShortsPage will cover it. Nothing to do here.
            homeLog.notice(
                "loadMoreShortsIfNeeded: skipped count=\(shortsVideos.count) hasToken=\(shortsNextPageToken != nil) loading=\(isLoadingMoreShorts)"
            )
            return
        }
        isLoadingMoreShorts = true
        defer { isLoadingMoreShorts = false }
        var loopIteration = 0
        var emptyPages = 0
        // Loop until we have at least `threshold` items or pages run out.
        while shortsVideos.count < threshold, shortsNextPageToken != nil {
            loopIteration += 1
            homeLog.notice(
                "loadMoreShortsIfNeeded: loop=\(loopIteration) count=\(shortsVideos.count) threshold=\(threshold)")
            guard await keepsPaging(afterPageAdded: fetchOneShortsPage(), emptyPages: &emptyPages) else { break }
        }
    }

    /// Continues fetching Shorts pages in the background (shelf continuation, or the
    /// subscriptions continuation in the feed fallback) until `homeShortsVideos.count` reaches
    /// `preloadHighThreshold` or both sources are exhausted. Started as a
    /// fire-and-forget task after `load()` finishes its fast initial fill
    /// (`loadMoreShortsIfNeeded`), so the Shorts row keeps growing for an
    /// endless-scroll experience without delaying `isRefreshing = false`.
    private func preloadMoreShorts() async {
        #if os(tvOS)
        let preloadHighThreshold = 50
        #else
        let preloadHighThreshold = 40
        #endif
        guard !isLoadingMoreShorts else { return }
        // YouTube's Shorts sequence costs a metadata request per Short (for the card
        // titles), so it isn't paged ahead in the background: the row pages it as the
        // user scrolls (`loadNextShortsPage()`).
        if shortsNextPageToken?.hasPrefix(ShortsSequenceParams.shelfTokenPrefix) == true {
            homeLog.notice("preloadMoreShorts: skipped — the Shorts sequence pages on demand")
            return
        }
        isLoadingMoreShorts = true
        defer { isLoadingMoreShorts = false }
        var loopIteration = 0
        var emptyPages = 0
        while !Task.isCancelled, homeShortsVideos.count < preloadHighThreshold {
            guard shortsNextPageToken != nil || subsShortsToken != nil else {
                homeLog.notice(
                    "preloadMoreShorts: stopping — no continuation tokens left, count=\(homeShortsVideos.count)")
                break
            }
            loopIteration += 1
            homeLog.notice(
                "preloadMoreShorts: iteration=\(loopIteration) count=\(homeShortsVideos.count)/\(preloadHighThreshold)")
            guard await keepsPaging(afterPageAdded: fetchOneShortsPage(), emptyPages: &emptyPages) else { break }
        }
    }

    /// How many pages in a row may add nothing (all duplicates) before a paging loop
    /// gives up although a next-page token is left.
    static let maxEmptyShortsPagesInARow = 3

    /// Whether a paging loop goes on after a page: always after one that added
    /// Shorts; after one that added nothing only while `maxEmptyShortsPagesInARow`
    /// isn't reached — a page of duplicates doesn't mean the feed has ended.
    private func keepsPaging(afterPageAdded added: Bool, emptyPages: inout Int) -> Bool {
        if added {
            emptyPages = 0
            return true
        }
        emptyPages += 1
        guard emptyPages < Self.maxEmptyShortsPagesInARow else {
            homeLog.notice("Shorts paging: stopping — \(emptyPages) pages in a row added nothing")
            return false
        }
        return true
    }

    // MARK: - Private fetch helpers

    /// Fetches the Shorts shelf (`fetchShorts()`: the reel sequence, falling back to
    /// the `#shorts` search). Errors yield an empty shelf.
    private static func fetchShortsVideos(api: any InnerTubeAPIProtocol) async -> ([Video], String?) {
        do {
            let group = try await api.fetchShorts()
            let hasToken = group.nextPageToken != nil
            homeLog.notice("fetchShortsVideos → \(group.videos.count) shorts hasToken=\(hasToken)")
            return (group.videos, group.nextPageToken)
        } catch {
            homeLog.error("fetchShortsVideos failed: \(error.localizedDescription)")
            return ([], nil)
        }
    }

    /// Non-isolated so child tasks run on the global executor and network
    /// calls can overlap.
    private static func fetchVideos(
        type: BrowseSection.SectionType, api: any InnerTubeAPIProtocol
    ) async -> ([Video], String?) {
        do {
            switch type {
            case .subscriptions:
                let group = try await api.fetchSubscriptions()
                let shortsCount = group.videos.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchVideos subs: total=\(group.videos.count) shorts=\(shortsCount) regular=\(group.videos.count - shortsCount)"
                )
                return (Array(group.videos.prefix(InnerTubeClients.maxVideoResults)), group.nextPageToken)
            case .home:
                let rows = try await api.fetchHomeRows()
                let token = rows.last(where: { $0.nextPageToken != nil })?.nextPageToken
                var seen = Set<String>()
                let deduped = rows.flatMap(\.videos).filter { seen.insert($0.id).inserted }
                let fetchedShortsCount = deduped.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchVideos home: total=\(deduped.count) shorts=\(fetchedShortsCount) regular=\(deduped.count - fetchedShortsCount)"
                )
                if deduped.isEmpty {
                    // Home feed empty (no watch history / feedNudgeRenderer) — fall back to popular
                    let popular = try await api.search(query: "popular")
                    return (popular.videos, popular.nextPageToken)
                }
                return (Array(deduped.prefix(InnerTubeClients.maxVideoResults)), token)
            default:
                return ([], nil)
            }
        } catch {
            homeLog.error("HomeViewModel fetch \(String(describing: type)): \(error.localizedDescription)")
            return ([], nil)
        }
    }

    private static func fetchMoreVideos(
        type: BrowseSection.SectionType, token: String, api: any InnerTubeAPIProtocol
    ) async -> ([Video], String?) {
        do {
            switch type {
            case .subscriptions:
                let group = try await retryWithBackoff(label: "HomeVM.subs") {
                    try await api.fetchSubscriptions(continuationToken: token)
                }
                let shortsCount = group.videos.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchMoreVideos subs: total=\(group.videos.count) shorts=\(shortsCount) regular=\(group.videos.count - shortsCount)"
                )
                return (group.videos, group.nextPageToken)
            case .home:
                let rows = try await retryWithBackoff(label: "HomeVM.home") {
                    try await api.fetchHomeRows(continuationToken: token)
                }
                let nextToken = rows.last(where: { $0.nextPageToken != nil })?.nextPageToken
                // Dedup within the page — YouTube can return the same video ID
                // in multiple shelves of the same continuation response.
                var seen = Set<String>()
                let deduped = rows.flatMap(\.videos).filter { seen.insert($0.id).inserted }
                return (deduped, nextToken)
            default:
                return ([], nil)
            }
        } catch {
            homeLog.error("HomeViewModel loadMore \(String(describing: type)): \(error.localizedDescription)")
            return ([], nil)
        }
    }
}
