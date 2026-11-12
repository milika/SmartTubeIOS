import Foundation
import Network
import os

private let cacheLog = Logger(subsystem: appSubsystem, category: "PreloadCache")

// MARK: - VideoPreloadCache
//
// An in-memory, actor-isolated cache for all per-video API responses that
// PlaybackViewModel needs before playback can start.
//
// Design goals:
//  - Zero-contention reads/writes via actor isolation (no locks needed)
//  - TTL-based expiry per data type (stream URLs expire earliest, ~5.5 h)
//  - LRU eviction: keeps at most `maxVideoEntries` videos worth of data
//  - Active prefetch tasks are tracked so duplicates are skipped and
//    tasks can be cancelled when the user navigates away
//
// Usage:
//  1. Call `prefetch(videoId:...)` from a VideoCardView `.task` modifier
//     as cards become visible.
//  2. In PlaybackViewModel.loadAsync(), call `consume(videoId:)` first —
//     if the cache holds fresh data you avoid all network calls.
//  3. After a live fetch, store results with `store(...)`.

// MARK: - PrefetchPriority

/// Priority tiers for the prefetch queue.
/// Higher raw values are dispatched first.
public enum PrefetchPriority: Int, Comparable, CaseIterable, Sendable {
    case speculative = 0  // neighbour prefetch — likely next video
    case visible = 1  // VideoCardView onAppear
    case immediate = 2  // reserved for near-play scenarios
    case userFocused = 3  // reserved for user-initiated loads

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - PrefetchRequest

private struct PrefetchRequest: Sendable {
    let videoId: String
    let sponsorCategories: Set<SponsorSegment.Category>
    let authToken: String?
    let priority: PrefetchPriority
    let enqueuedAt: Date
}

public actor VideoPreloadCache {

    // MARK: - Singleton

    public static let shared = VideoPreloadCache()

    // MARK: - Owned service instances
    //
    // The cache owns lightweight service instances so callers (e.g. VideoCardView)
    // only need to supply `videoId`, `isAuthenticated`, and `sponsorCategories` —
    // no service references need to flow through the view hierarchy.
    // Auth token is kept in sync via `setAuthToken(_:)`.
    // Services are injected via init so tests can substitute pre-configured instances.

    private let api: InnerTubeAPI
    private let sponsorBlock: SponsorBlockService
    private let deArrow: DeArrowService

    // MARK: - TTL constants

    /// iOS-client CDN stream URLs expire after ~6 h; use 5 h 30 m to be safe.
    public static let playerInfoTTL: TimeInterval = 5.5 * 3600
    /// Related-video list can change; 20-min window covers typical session length.
    public static let nextInfoTTL: TimeInterval = 20 * 60
    /// End cards and SponsorBlock/DeArrow data are stable for hours.
    public static let endCardsTTL: TimeInterval = 4 * 3600
    public static let sponsorTTL: TimeInterval = 2 * 3600
    public static let deArrowTTL: TimeInterval = 4 * 3600

    // MARK: - LRU cap

    /// Maximum number of distinct video IDs kept in memory.
    private static let maxVideoEntries = 30

    // MARK: - Cache entry

    struct CacheEntry<T: Sendable>: Sendable {
        let value: T
        let storedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(storedAt) > ttl }
    }

    // MARK: - Sub-caches (keyed by videoId)

    private var playerInfoCache: [String: CacheEntry<PlayerInfo>] = [:]
    private var nextInfoCache: [String: CacheEntry<NextInfo>] = [:]
    private var endCardsCache: [String: CacheEntry<[EndCard]>] = [:]
    private var sponsorCache: [String: CacheEntry<[SponsorSegment]>] = [:]
    private var deArrowCache: [String: CacheEntry<DeArrowService.BrandingInfo>] = [:]
    /// WKWebView-extracted HLS master manifest URLs keyed by videoId.
    /// NOT cleared by consume() — persists so that re-plays and neighbour navigation
    /// skip the 5–9 s WKWebView extraction step when the URL is still fresh.
    private var wkHLSCache: [String: CacheEntry<URL>] = [:]
    /// BotGuard proof-of-origin tokens keyed by videoId, stored alongside the HLS URL.
    /// These survive the YouTubeWebViewHLSExtractor.extractedPoToken reset that happens
    /// at the start of each new extractHLSURL call, so Phase -1a can always retrieve
    /// the preWarm-extracted token regardless of when wkHLSEarlyTask resets the field.
    private var wkHLSPoTokenCache: [String: String] = [:]
    /// Tracks whether the wkHLS URL was stored by a background preWarm extraction (true)
    /// or by a live race playback path (false). Phase -1a skips the probe for preWarm + pot=nil
    /// entries because preWarm URLs contain `pfa/1` in variant playlist paths, which causes
    /// segment-level 403s when no pot= is available. Live-race URLs do not have this restriction.
    private var wkHLSIsPreWarmCache: [String: Bool] = [:]

    // MARK: - Access order (LRU)

    /// Ordered from oldest to newest access.
    private var accessOrder: [String] = []

    // MARK: - Active prefetch tasks

    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    // MARK: - In-flight coalescing
    //
    // Ensures concurrent live-load and prefetch calls for the same video ID
    // share a single network request rather than duplicating it.

    private var inFlightPlayerFetches: [String: Task<PlayerInfo?, Never>] = [:]

    // MARK: - Priority queue + worker pool
    //
    // Replaces the old activePrefetchCount + silent-drop guard (FM-1).
    // Enqueues requests sorted by priority; drains the queue with a worker pool.
    // Phase K (task #30) will make the cap network-aware.

    private var prefetchQueue: [PrefetchRequest] = []
    internal static let maxQueueDepth = 20  // internal for tests + Phase K
    internal static let maxWorkersWiFi = 5  // internal for Phase K override
    internal static let maxWorkersCellular = 2  // internal for Phase K override
    private var activeWorkerCount = 0

    // MARK: - Disk cache (Phase J)

    private let disk = VideoDiskCache()

    // MARK: - Network-aware throttling (Phase K)

    nonisolated private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath? = nil

    private init(
        api: InnerTubeAPI = InnerTubeAPI(),
        sponsorBlock: SponsorBlockService = SponsorBlockService(),
        deArrow: DeArrowService = DeArrowService()
    ) {
        self.api = api
        self.sponsorBlock = sponsorBlock
        self.deArrow = deArrow
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.updatePath(path) }
        }
        pathMonitor.start(queue: .global(qos: .background))
    }

    // MARK: - Public: auth token

    /// Forward the current auth token so prefetch requests can make authenticated calls.
    /// Call this from PlaybackViewModel.updateAuthToken and at app launch.
    public func setAuthToken(_ token: String?) async {
        cacheLog.notice("[auth] setAuthToken: \(token != nil ? "present" : "nil", privacy: .public)")
        await api.setAuthToken(token)
    }

    /// Forward the SAPISID cookie so prefetch WEB_CREATOR requests use SAPISIDHASH auth.
    public func setSAPISID(_ value: String?) async {
        await api.setSAPISID(value)
    }

    // MARK: - Public: prefetch

    /// Enqueues a background prefetch for all data types for `videoId`.
    /// Requests are sorted by `priority`; the queue is bounded at `maxQueueDepth`
    /// and evicts the lowest-priority item on overflow (enqueue-not-drop pattern).
    /// Pass the actual `authToken` value (not just a Bool) so the cache can
    /// sync it to its internal API before the prefetch requests fire —
    /// eliminating a race where prefetch starts before `setAuthToken` runs.
    public func prefetch(
        videoId: String,
        sponsorCategories: Set<SponsorSegment.Category>,
        authToken: String?,
        priority: PrefetchPriority = .visible
    ) {
        // Global kill-switch: DebugFlags.cachingDisabled covers both the hardcoded flag
        // and the --uitesting-disable-prefetch launch argument.
        if DebugFlags.cachingDisabled { return }
        // Playlist IDs are not video IDs — skip them to avoid wasted /player calls.
        let isPlaylistId = videoId == "WL" || videoId == "LL" || videoId.hasPrefix("PL")
        if isPlaylistId { return }
        // Skip if still fresh
        if let entry = playerInfoCache[videoId], !entry.isExpired { return }
        // Skip if already in-flight
        if prefetchTasks[videoId] != nil { return }
        // If already queued, upgrade priority if higher and re-sort
        if let idx = prefetchQueue.firstIndex(where: { $0.videoId == videoId }) {
            if priority > prefetchQueue[idx].priority {
                prefetchQueue[idx] = PrefetchRequest(
                    videoId: videoId,
                    sponsorCategories: sponsorCategories,
                    authToken: authToken,
                    priority: priority,
                    enqueuedAt: prefetchQueue[idx].enqueuedAt
                )
                prefetchQueue.sort { $0.priority > $1.priority }
            }
            return
        }
        // Overflow: evict the lowest-priority queued item before inserting
        if prefetchQueue.count >= Self.maxQueueDepth {
            prefetchQueue.removeLast()
        }
        // Insert maintaining descending-priority sort
        let request = PrefetchRequest(
            videoId: videoId,
            sponsorCategories: sponsorCategories,
            authToken: authToken,
            priority: priority,
            enqueuedAt: .init()
        )
        let insertIdx = prefetchQueue.firstIndex(where: { $0.priority < priority }) ?? prefetchQueue.endIndex
        prefetchQueue.insert(request, at: insertIdx)
        let qDepth = prefetchQueue.count
        let wCount = activeWorkerCount
        cacheLog.notice(
            "[prefetch] ENQUEUE \(videoId, privacy: .public) priority=\(priority.rawValue, privacy: .public) queueDepth=\(qDepth, privacy: .public) workers=\(wCount, privacy: .public)"
        )
        drainQueue()
    }

    /// Cancels any in-flight prefetch for `videoId` and removes it from the queue.
    public func cancelPrefetch(for videoId: String) {
        prefetchQueue.removeAll { $0.videoId == videoId }
        prefetchTasks[videoId]?.cancel()
        prefetchTasks.removeValue(forKey: videoId)
    }

    // MARK: - Private: worker pool drain

    /// Updates the tracked network path and re-evaluates the worker pool.
    private func updatePath(_ path: NWPath) {
        currentPath = path
        drainQueue()
    }

    /// Maximum concurrent prefetch workers for the current network path.
    /// Returns 0 when offline — new prefetches are paused but in-flight tasks continue.
    var networkCap: Int {  // internal for tests
        guard let path = currentPath, path.status == .satisfied else {
            // No path yet or path unsatisfied — allow WiFi workers until first update.
            return currentPath == nil ? Self.maxWorkersWiFi : 0
        }
        if path.isConstrained || path.isExpensive {
            return Self.maxWorkersCellular
        }
        return Self.maxWorkersWiFi
    }

    /// Data types allowed for prefetch on the current network path.
    /// Cellular/expensive paths skip large cosmetic fetches (endCards, deArrow).
    var allowedPrefetchDataTypes: Set<String> {  // internal for tests
        guard let path = currentPath, path.status == .satisfied else {
            return currentPath == nil
                ? ["playerInfo", "nextInfo", "sponsorSegments", "endCards", "deArrowBranding"] : []
        }
        if path.isConstrained || path.isExpensive {
            return ["playerInfo", "nextInfo", "sponsorSegments"]
        }
        return ["playerInfo", "nextInfo", "sponsorSegments", "endCards", "deArrowBranding"]
    }

    /// Starts worker tasks up to the current cap until the queue is empty.
    /// Called by `prefetch()` and by each worker on completion.
    func drainQueue(workerCap: Int? = nil) {
        let cap = workerCap ?? networkCap
        guard cap > 0 else { return }  // paused when offline
        while activeWorkerCount < cap, !prefetchQueue.isEmpty {
            let request = prefetchQueue.removeFirst()
            guard prefetchTasks[request.videoId] == nil else { continue }
            activeWorkerCount += 1
            let task = Task(priority: .background) {
                await self.runPrefetch(
                    videoId: request.videoId,
                    sponsorCategories: request.sponsorCategories,
                    authToken: request.authToken
                )
                self.activeWorkerCount = max(0, self.activeWorkerCount - 1)
                self.drainQueue()
            }
            prefetchTasks[request.videoId] = task
        }
    }

    // MARK: - Public: in-flight coalescing

    /// Returns a shared Task that resolves to the player info for `videoId`.
    /// If a fetch is already in-flight (from a concurrent prefetch or live load),
    /// the existing Task is returned — no duplicate network request is made.
    public func getOrFetchPlayerInfo(videoId: String) -> Task<PlayerInfo?, Never> {
        if let existing = inFlightPlayerFetches[videoId] {
            cacheLog.notice("[coalesce] returning existing in-flight task for \(videoId, privacy: .public)")
            return existing
        }
        cacheLog.notice("[coalesce] creating new in-flight task for \(videoId, privacy: .public)")
        let task = Task<PlayerInfo?, Never>(priority: .userInitiated) {
            let result = try? await self.api.fetchPlayerInfo(videoId: videoId)
            self.inFlightPlayerFetches.removeValue(forKey: videoId)
            return result
        }
        inFlightPlayerFetches[videoId] = task
        return task
    }

    /// Returns the in-flight player fetch task for `videoId`, or `nil` if none is running.
    /// Used by `loadAsync` to coalesce with a concurrent prefetch without losing error context.
    public func inFlightPlayerFetch(videoId: String) -> Task<PlayerInfo?, Never>? {
        inFlightPlayerFetches[videoId]
    }

    // MARK: - Public: consume (cache-first read)

    /// Returns whatever fresh cached data exists for `videoId`, or `nil` fields
    /// for data that is missing or expired. Callers fetch only the missing pieces.
    /// SWR-eligible types (nextInfo, endCards, sponsorSegments, deArrowBranding) are
    /// returned even when stale, with the type added to `staleFields` — so callers can
    /// use the value immediately and revalidate in the background.
    public func consume(videoId: String) -> CachedVideoData {
        if DebugFlags.cachingDisabled {
            cacheLog.notice("[consume] caching disabled — returning empty for \(videoId, privacy: .public)")
            return CachedVideoData(
                playerInfo: nil, nextInfo: nil,
                endCards: nil, sponsorSegments: nil, deArrowBranding: nil,
                staleFields: [])
        }
        touch(videoId)
        // Disk warm-up (Phase J): populate in-memory cache from disk on cold path.
        // Disk-loaded entries use storedAt: .distantPast so SWR treats them as stale
        // and schedules background revalidation via Phase 2.
        if nextInfoCache[videoId] == nil,
            let fromDisk = disk.load(NextInfo.self, videoId: videoId, dataType: "nextInfo")
        {
            nextInfoCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.nextInfoTTL)
        }
        if endCardsCache[videoId] == nil,
            let fromDisk = disk.load([EndCard].self, videoId: videoId, dataType: "endCards")
        {
            endCardsCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.endCardsTTL)
        }
        if sponsorCache[videoId] == nil,
            let fromDisk = disk.load([SponsorSegment].self, videoId: videoId, dataType: "sponsorSegments")
        {
            sponsorCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.sponsorTTL)
        }
        if deArrowCache[videoId] == nil,
            let fromDisk = disk.load(DeArrowService.BrandingInfo.self, videoId: videoId, dataType: "deArrowBranding")
        {
            deArrowCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.deArrowTTL)
        }
        var staleFields = Set<CachedVideoData.DataType>()
        let data = CachedVideoData(
            playerInfo: fresh(playerInfoCache[videoId]),
            nextInfo: staleOrFresh(nextInfoCache[videoId], dataType: .nextInfo, into: &staleFields),
            endCards: staleOrFresh(endCardsCache[videoId], dataType: .endCards, into: &staleFields),
            sponsorSegments: staleOrFresh(sponsorCache[videoId], dataType: .sponsorSegments, into: &staleFields),
            deArrowBranding: staleOrFresh(deArrowCache[videoId], dataType: .deArrowBranding, into: &staleFields),
            staleFields: staleFields
        )
        cacheLog.notice(
            "[consume] \(videoId, privacy: .public) — player=\(data.playerInfo != nil, privacy: .public) next=\(data.nextInfo != nil, privacy: .public) endCards=\(data.endCards != nil, privacy: .public) sponsor=\(data.sponsorSegments != nil, privacy: .public) deArrow=\(data.deArrowBranding != nil, privacy: .public) stale=\(staleFields.count, privacy: .public) complete=\(data.isComplete, privacy: .public)"
        )
        return data
    }

    // MARK: - Public: store (write after live fetch)

    public func store(playerInfo: PlayerInfo, for videoId: String) {
        cacheLog.notice(
            "[store] playerInfo \(videoId, privacy: .public) formats=\(playerInfo.formats.count, privacy: .public) hls=\(playerInfo.hlsURL != nil, privacy: .public) adaptive=\(playerInfo.bestAdaptiveVideoURL != nil, privacy: .public)"
        )
        playerInfoCache[videoId] = CacheEntry(value: playerInfo, storedAt: .init(), ttl: Self.playerInfoTTL)
        touch(videoId)
    }


    public func store(nextInfo: NextInfo, for videoId: String) {
        cacheLog.debug(
            "[store] nextInfo \(videoId, privacy: .public) related=\(nextInfo.relatedVideos.count, privacy: .public) chapters=\(nextInfo.chapters.count, privacy: .public)"
        )
        nextInfoCache[videoId] = CacheEntry(value: nextInfo, storedAt: .init(), ttl: Self.nextInfoTTL)
        disk.store(nextInfo, videoId: videoId, dataType: "nextInfo")
        touch(videoId)
    }

    public func store(endCards: [EndCard], for videoId: String) {
        cacheLog.debug("[store] endCards \(videoId, privacy: .public) count=\(endCards.count, privacy: .public)")
        endCardsCache[videoId] = CacheEntry(value: endCards, storedAt: .init(), ttl: Self.endCardsTTL)
        disk.store(endCards, videoId: videoId, dataType: "endCards")
        touch(videoId)
    }

    public func store(sponsorSegments: [SponsorSegment], for videoId: String) {
        cacheLog.debug(
            "[store] sponsorSegments \(videoId, privacy: .public) count=\(sponsorSegments.count, privacy: .public)")
        sponsorCache[videoId] = CacheEntry(value: sponsorSegments, storedAt: .init(), ttl: Self.sponsorTTL)
        disk.store(sponsorSegments, videoId: videoId, dataType: "sponsorSegments")
        touch(videoId)
    }

    public func store(deArrowBranding: DeArrowService.BrandingInfo, for videoId: String) {
        cacheLog.debug(
            "[store] deArrowBranding \(videoId, privacy: .public) hasTitle=\(deArrowBranding.title != nil, privacy: .public)"
        )
        deArrowCache[videoId] = CacheEntry(value: deArrowBranding, storedAt: .init(), ttl: Self.deArrowTTL)
        disk.store(deArrowBranding, videoId: videoId, dataType: "deArrowBranding")
        touch(videoId)
    }

    /// Stores the WKWebView-extracted HLS master manifest URL for a video.
    /// TTL matches the `expire=` lifetime of signed manifest URLs (~6h) with a 2h safety margin.
    /// NOT subject to consume() eviction — survives across multiple load() calls.
    /// - Parameter isPreWarm: Pass `true` when called from background `preWarm()` extraction,
    ///   `false` when called from a live race playback path (tryWebViewHLS / Path B win).
    ///   Phase -1a consults this flag to skip the HEAD probe for preWarm + pot=nil entries.
    public func store(wkHLSManifestURL url: URL, for videoId: String, isPreWarm: Bool = false) {
        cacheLog.notice(
            "[store] wkHLS \(videoId) origin=\(isPreWarm ? "preWarm" : "liveRace") url=\(url.absoluteString.prefix(80))"
        )
        wkHLSCache[videoId] = CacheEntry(value: url, storedAt: .init(), ttl: 4 * 3_600)
        wkHLSIsPreWarmCache[videoId] = isPreWarm
    }

    /// Returns `true` when the cached wkHLS URL was stored by a background preWarm extraction.
    /// Returns `false` for live-race extracted URLs or when no URL is cached.
    public func cachedWKHLSIsPreWarm(for videoId: String) -> Bool {
        wkHLSIsPreWarmCache[videoId] ?? false
    }

    /// Returns the cached WKWebView HLS master manifest URL if still within TTL, else nil.
    public func cachedWKHLSURL(for videoId: String) -> URL? {
        if DebugFlags.cachingDisabled { return nil }
        guard let entry = wkHLSCache[videoId] else { return nil }
        if entry.isExpired {
            wkHLSCache.removeValue(forKey: videoId)
            return nil
        }
        return entry.value
    }

    /// Returns true if the cached WKWebView HLS URL was stored within the last `seconds` seconds.
    /// Phase -1a uses this to skip the HEAD probe for recently-extracted URLs — the URL is
    /// guaranteed fresh (CDN session active) and the probe round-trip (~0.22s) is wasted work.
    /// Default threshold: 10s (covers the double-preWarm window before the heartbeat fires).
    public func isWKHLSURLFresh(for videoId: String, within seconds: TimeInterval = 10) -> Bool {
        guard let entry = wkHLSCache[videoId] else { return false }
        return Date().timeIntervalSince(entry.storedAt) < seconds
    }

    /// Stores the BotGuard pot= token that accompanied the WKWebView HLS URL extraction.
    /// The token is NOT subject to TTL — it's evicted together with the HLS URL in
    /// `invalidateWKHLSURL(for:)`. This is the stable storage point for Phase -1a:
    /// unlike `YouTubeWebViewHLSExtractor.extractedPoToken`, this entry survives the
    /// nil-reset that happens at the start of every new `extractHLSURL` call.
    public func store(wkHLSPoToken token: String, for videoId: String) {
        wkHLSPoTokenCache[videoId] = token
    }

    /// Returns the cached pot= token for a video, or nil if none was stored.
    public func cachedPoToken(for videoId: String) -> String? {
        if DebugFlags.cachingDisabled { return nil }
        return wkHLSPoTokenCache[videoId]
    }

    // MARK: - Public: auth invalidation

    /// Call on sign-out: like-status in nextInfo is account-bound.
    public func evictAuthSensitiveData() {
        cacheLog.notice(
            "[evict] auth sign-out — clearing nextInfoCache (\(self.nextInfoCache.count, privacy: .public) entries)"
        )
        nextInfoCache.removeAll()
        // BUG-013 fix: also purge disk so nextInfo (likeStatus) cannot be read back after sign-out.
        disk.removeAll()
    }

    /// Call when a 403 is received for a cached player-info URL.
    /// The cached URL is IP-bound and is now stale; evicting forces a fresh fetch on next load.
    public func invalidatePlayerInfo(for videoId: String) {
        guard playerInfoCache[videoId] != nil else { return }
        cacheLog.notice("[evict] 403 — invalidating playerInfoCache for \(videoId, privacy: .public)")
        playerInfoCache.removeValue(forKey: videoId)
    }

    /// Call when the cached WKWebView HLS URL returns 403 (expired signed URL).
    /// Evicting forces a fresh WKWebView extraction on the next load of this video.
    /// Also clears the associated pot= token so Phase -1a won't use an orphaned token.
    public func invalidateWKHLSURL(for videoId: String) {
        guard wkHLSCache[videoId] != nil else { return }
        cacheLog.notice("[evict] 403 — invalidating wkHLSCache for \(videoId, privacy: .public)")
        wkHLSCache.removeValue(forKey: videoId)
        wkHLSPoTokenCache.removeValue(forKey: videoId)
        wkHLSIsPreWarmCache.removeValue(forKey: videoId)
    }

    // MARK: - Private: prefetch implementation

    private func runPrefetch(
        videoId: String,
        sponsorCategories: Set<SponsorSegment.Category>,
        authToken: String?
    ) async {
        guard !Task.isCancelled else { return }
        let startedAt = Date()
        let allowed = allowedPrefetchDataTypes
        cacheLog.notice(
            "[prefetch] START \(videoId, privacy: .public) allowed=\(allowed.sorted().joined(separator: ","), privacy: .public)"
        )

        // Route through getOrFetchPlayerInfo so a concurrent live-load for the
        // same video reuses this in-flight task instead of issuing a second request.
        let playerFetchTask = getOrFetchPlayerInfo(videoId: videoId)
        // Gate optional fetches on the current network path (Phase K).
        async let nextResult = allowed.contains("nextInfo") ? (try? await api.fetchNextInfo(videoId: videoId)) : nil
        async let endCardsResult = allowed.contains("endCards") ? (try? await api.fetchEndCards(videoId: videoId)) : nil
        async let sponsorResult = await sponsorBlock.fetchSegments(videoId: videoId, categories: sponsorCategories)
        async let deArrowResult =
            allowed.contains("deArrowBranding") ? await deArrow.fetchBranding(videoId: videoId) : nil

        let (next, cards, sponsor, dearrow) =
            await (nextResult, endCardsResult, sponsorResult, deArrowResult)
        let player = await playerFetchTask.value

        guard !Task.isCancelled else { return }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))

        if let player { store(playerInfo: player, for: videoId) }
        if let next { store(nextInfo: next, for: videoId) }
        if let cards { store(endCards: cards, for: videoId) }
        store(sponsorSegments: sponsor, for: videoId)
        if let dearrow { store(deArrowBranding: dearrow, for: videoId) }

        cacheLog.notice(
            "[prefetch] DONE \(videoId, privacy: .public) elapsed=\(elapsed, privacy: .public) playerInfo=\(player != nil, privacy: .public) next=\(next != nil, privacy: .public) endCards=\(cards != nil, privacy: .public) sponsor=\(sponsor.count, privacy: .public) deArrow=\(dearrow != nil, privacy: .public)"
        )
        prefetchTasks.removeValue(forKey: videoId)
    }

    // MARK: - Private: LRU helpers

    private func touch(_ videoId: String) {
        accessOrder.removeAll { $0 == videoId }
        accessOrder.append(videoId)
        if accessOrder.count > Self.maxVideoEntries {
            let evict = accessOrder.removeFirst()
            cacheLog.notice(
                "[lru] EVICT \(evict, privacy: .public) — cache full (\(Self.maxVideoEntries, privacy: .public) entries)"
            )
            playerInfoCache.removeValue(forKey: evict)
            nextInfoCache.removeValue(forKey: evict)
            endCardsCache.removeValue(forKey: evict)
            sponsorCache.removeValue(forKey: evict)
            deArrowCache.removeValue(forKey: evict)
            prefetchTasks[evict]?.cancel()
            prefetchTasks.removeValue(forKey: evict)
        }
    }

    private func fresh<T: Sendable>(_ entry: CacheEntry<T>?) -> T? {
        guard let entry, !entry.isExpired else { return nil }
        return entry.value
    }

    /// Returns the cached value regardless of expiry, adding `dataType` to `staleFields`
    /// if the entry is expired. Returns `nil` only when no entry exists at all.
    private func staleOrFresh<T: Sendable>(
        _ entry: CacheEntry<T>?,
        dataType: CachedVideoData.DataType,
        into staleFields: inout Set<CachedVideoData.DataType>
    ) -> T? {
        guard let entry else { return nil }
        if entry.isExpired { staleFields.insert(dataType) }
        return entry.value
    }
}

// MARK: - CachedVideoData

/// A snapshot of whatever pre-fetched data is available for a video.
/// Fields that are `nil` were not cached or have expired — callers must fetch those live.
/// Fields in `staleFields` have data but are past their TTL — callers can use the stale
/// value immediately and revalidate in the background (stale-while-revalidate pattern).
public struct CachedVideoData: Sendable {

    /// SWR-eligible data types. `playerInfo` is NOT SWR-eligible
    /// (CDN-bound — stale stream URLs cause 403).
    public enum DataType: CaseIterable, Sendable {
        case nextInfo, endCards, sponsorSegments, deArrowBranding
    }

    public let playerInfo: PlayerInfo?
    public let nextInfo: NextInfo?
    public let endCards: [EndCard]?
    public let sponsorSegments: [SponsorSegment]?
    public let deArrowBranding: DeArrowService.BrandingInfo?
    /// Data types that are present but past their TTL. Non-empty means the value was
    /// returned stale and a background revalidation fetch should be scheduled.
    public var staleFields: Set<DataType>

    /// True when every field that is required for instant playback start is fresh.
    public var isComplete: Bool {
        playerInfo != nil && nextInfo != nil && sponsorSegments != nil
    }

    public init(
        playerInfo: PlayerInfo?,
        nextInfo: NextInfo?,
        endCards: [EndCard]?,
        sponsorSegments: [SponsorSegment]?,
        deArrowBranding: DeArrowService.BrandingInfo?,
        staleFields: Set<DataType>
    ) {
        self.playerInfo = playerInfo
        self.nextInfo = nextInfo
        self.endCards = endCards
        self.sponsorSegments = sponsorSegments
        self.deArrowBranding = deArrowBranding
        self.staleFields = staleFields
    }
}
