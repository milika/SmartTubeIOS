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
    ///   seedless feed (Shorts tab) whose first Short *is* included.
    public func fetchShortsFeed(seedVideoId: String? = nil) async throws -> ShortsFeedPage {
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
            guard let first = seedless.first, let params = seedless.sequenceParams else {
                throw APIError.decodingError("Seedless Shorts response had no first Short")
            }
            leading = [first]
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
