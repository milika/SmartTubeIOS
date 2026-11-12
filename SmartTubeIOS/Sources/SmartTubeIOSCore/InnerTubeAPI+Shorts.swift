import Foundation
import os

private let shortsLog = Logger(subsystem: appSubsystem, category: "ShortsFeed")

// MARK: - Shorts feed (YouTube's Shorts algorithm) + channel subscribe
//
// See `ShortsSequence.swift` for the endpoint shapes and parsers.

extension InnerTubeAPI {

    /// First page of YouTube's Shorts sequence.
    ///
    /// - Parameter seedVideoId: The Short the user tapped. The sequence then continues
    ///   from it (it is *not* included — callers put it first themselves). nil starts a
    ///   seedless feed (Shorts tab) whose first Short *is* included; that one reuses the
    ///   page a Shorts shelf just requested for this account (`ShortsFirstPageShare`).
    public func fetchShortsFeed(seedVideoId: String? = nil) async throws -> ShortsFeedPage {
        if seedVideoId == nil, let shared = shortsFirstPageShare.take(for: shortsAccount) {
            if let page = try? await shared.value {
                shortsLog.notice("Shorts feed: reusing the Shorts shelf's first page (\(page.videos.count) Shorts)")
                return page
            }
        }
        return try await requestShortsFeed(seedVideoId: seedVideoId)
    }

    /// The Bearer token and Brand Account a Shorts sequence is personalised for.
    private var shortsAccount: ShortsFirstPageShare.Account {
        ShortsFirstPageShare.Account(token: authToken, pageId: activeChannel.pageId)
    }

    /// `fetchShortsFeed(seedVideoId:)`'s request, without the shared page.
    private func requestShortsFeed(seedVideoId: String?) async throws -> ShortsFeedPage {
        var leading: [Video] = []
        let sequenceParams: String
        if let seedVideoId {
            sequenceParams = ShortsSequenceParams.seed(videoId: seedVideoId)
        } else {
            var body = makeBody(client: tvClientContext)
            body["inputType"] = ShortsSequenceParams.seedlessInputType
            body["params"] = ShortsSequenceParams.seedlessItemParams
            body["disablePlayerResponse"] = true
            let json = try await postReel(endpoint: "reel/reel_item_watch", body: body)
            let seedless = ShortsReelParser.parseSeedless(json)
            guard let params = seedless.sequenceParams else {
                throw APIError.decodingError("Seedless Shorts response had no sequence params")
            }
            // No first Short when it is an ad: the sequence still follows.
            leading = seedless.first.map { [$0] } ?? []
            sequenceParams = params
        }
        var body = makeBody(client: tvClientContext)
        body["sequenceParams"] = sequenceParams
        let page = try await fetchShortsSequencePage(body: body)
        let videos = leading + page.videos.filter { video in !leading.contains { $0.id == video.id } }
        return ShortsFeedPage(videos: videos, continuation: page.continuation, isPersonalized: page.isPersonalized)
    }

    /// Next page of the sequence started by `fetchShortsFeed(seedVideoId:)`.
    public func fetchShortsFeedMore(continuation: String) async throws -> ShortsFeedPage {
        var body = makeBody(client: tvClientContext)
        // Must be `continuation`, not `sequenceParams` — see ShortsSequence.swift.
        body["continuation"] = continuation
        return try await fetchShortsSequencePage(body: body)
    }

    /// Overlay metadata (title, channel, like/subscribe state, counts) for one Short.
    public func fetchShortMetadata(videoId: String) async throws -> ShortMetadata {
        var body = makeBody(client: tvClientContext)
        body["playerRequest"] = ["videoId": videoId]
        body["params"] = ShortsSequenceParams.metadataItemParams
        body["disablePlayerResponse"] = true
        let json = try await postReel(endpoint: "reel/reel_item_watch", body: body)
        guard let metadata = ShortsReelParser.parseMetadata(json, videoId: videoId) else {
            throw APIError.decodingError("reel_item_watch had no reelPlayerOverlayRenderer for \(videoId)")
        }
        return metadata
    }

    /// The Description sheet's content (title, channel, Likes/Views/date tiles,
    /// description text). Only the WEB client returns the structured description, so
    /// this is an anonymous WEB call (the TV Bearer token is rejected there). It asks
    /// for the device language because the tiles' labels are shown verbatim.
    public func fetchShortDescription(videoId: String) async throws -> ShortDescription {
        var context = webClientContext
        if var client = context["client"] as? [String: Any] {
            if let language = Locale.current.language.languageCode?.identifier { client["hl"] = language }
            if let region = Locale.current.region?.identifier { client["gl"] = region }
            context["client"] = client
        }
        var body = makeBody(client: context)
        body["playerRequest"] = ["videoId": videoId]
        body["params"] = ShortsSequenceParams.metadataItemParams
        body["disablePlayerResponse"] = true
        let json = try await post(endpoint: "reel/reel_item_watch", body: body)
        guard let description = ShortsDescriptionParser.parse(json, videoId: videoId) else {
            throw APIError.decodingError("reel_item_watch had no structured description for \(videoId)")
        }
        return description
    }

    /// One page of YouTube's Shorts sequence for a Shorts *shelf* (Home/Browse rows):
    /// personalised when signed in, with titles and channels filled in, because
    /// sequence entries carry only the id and thumbnail. `continuation` nil starts a
    /// seedless sequence. The returned `nextPageToken` carries the `reel:` prefix that
    /// `fetchShortsMore(continuationToken:)` routes back here.
    public func fetchShortsShelf(continuation: String?) async throws -> VideoGroup {
        let page: ShortsFeedPage
        if let continuation {
            page = try await fetchShortsFeedMore(continuation: continuation)
        } else {
            // Offered to the Shorts tab as soon as it starts, not after the titles.
            let request = Task { try await self.requestShortsFeed(seedVideoId: nil) }
            shortsFirstPageShare.offer(request, for: shortsAccount)
            page = try await request.value
        }
        let videos = await withShortTitles(page.videos)
        return VideoGroup(
            title: "Shorts", videos: videos,
            nextPageToken: page.continuation.map { ShortsSequenceParams.shelfTokenPrefix + $0 })
    }

    /// Subscribes the signed-in account to `channelId` (requires authentication).
    public func subscribe(channelId: String) async throws {
        guard authToken != nil else { throw APIError.notAuthenticated }
        var body = makeBody(client: tvClientContext)
        body["channelIds"] = [channelId]
        _ = try await postTV(endpoint: "subscription/subscribe", body: body)
    }

    /// Unsubscribes the signed-in account from `channelId` (requires authentication).
    public func unsubscribe(channelId: String) async throws {
        guard authToken != nil else { throw APIError.notAuthenticated }
        var body = makeBody(client: tvClientContext)
        body["channelIds"] = [channelId]
        _ = try await postTV(endpoint: "subscription/unsubscribe", body: body)
    }

    // MARK: Private

    /// Fills title/channel from each Short's overlay metadata, concurrently. A Short
    /// whose metadata fails keeps its empty title rather than being dropped.
    private func withShortTitles(_ videos: [Video]) async -> [Video] {
        let fetched = await withTaskGroup(of: (Int, ShortMetadata?).self) { group in
            for (index, video) in videos.enumerated() {
                group.addTask { (index, try? await self.fetchShortMetadata(videoId: video.id)) }
            }
            var results: [Int: ShortMetadata] = [:]
            for await (index, metadata) in group {
                if let metadata { results[index] = metadata }
            }
            return results
        }
        var titled = videos
        for (index, metadata) in fetched {
            titled[index].title = metadata.title
            titled[index].channelTitle = metadata.channelTitle
            titled[index].channelId = metadata.channelId
        }
        return titled
    }

    private func fetchShortsSequencePage(body: [String: Any]) async throws -> ShortsFeedPage {
        let json = try await postReel(endpoint: "reel/reel_watch_sequence", body: body)
        let parsed = ShortsReelParser.parseSequence(json)
        let loggedIn = ShortsReelParser.parseLoggedIn(json)
        shortsLog.notice(
            "reel_watch_sequence → \(parsed.videos.count, privacy: .public) Shorts, logged_in=\(loggedIn.map { $0 ? "1" : "0" } ?? "?", privacy: .public), more=\(parsed.continuation != nil, privacy: .public)"
        )
        return ShortsFeedPage(
            videos: parsed.videos, continuation: parsed.continuation, isPersonalized: loggedIn ?? false)
    }

    /// `postTV` with Bearer when signed in. If YouTube rejects the authenticated reel
    /// call with a client error, retry signed out — the non-personalised sequence is
    /// better than no feed at all.
    private func postReel(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard authToken != nil else { return try await postTV(endpoint: endpoint, body: body, useAuth: false) }
        do {
            return try await postTV(endpoint: endpoint, body: body)
        } catch APIError.httpError(let code) where (400..<500).contains(code) {
            shortsLog.notice(
                "/\(endpoint, privacy: .public) rejected signed-in (HTTP \(code, privacy: .public)) — retrying signed out"
            )
            return try await postTV(endpoint: endpoint, body: body, useAuth: false)
        }
    }
}
