import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Browse endpoints

extension InnerTubeAPI {

    // MARK: - Visitor data helper

    /// Extracts `responseContext.visitorData` from a browse response and stores it.
    /// The stored token is included in subsequent home-feed requests so YouTube can
    /// tailor recommendations to this specific device/session.
    func updateVisitorData(from response: [String: Any]) {
        guard let ctx = response["responseContext"] as? [String: Any],
            let vd = ctx["visitorData"] as? String, !vd.isEmpty
        else { return }
        visitorData = vd
    }

    // MARK: - Home

    /// Fetches the home feed.
    /// When authenticated, uses TVHTML5 on youtubei.googleapis.com for a personalised feed.
    /// When unauthenticated, uses the WEB client on www.youtube.com for the default feed.
    public func fetchHome(continuationToken: String? = nil) async throws -> VideoGroup {
        let isAuth = authToken != nil
        var body = makeBody(
            client: isAuth ? tvClientContext : webClientContext,
            continuationToken: continuationToken,
            includeVisitorData: true)
        if continuationToken == nil {
            body["browseId"] = "FEwhat_to_watch"
        }
        let data =
            isAuth
            ? try await postTV(endpoint: "browse", body: body)
            : try await post(endpoint: "browse", body: body)
        updateVisitorData(from: data)
        return try parseVideoGroup(from: data, title: BrowseSection.SectionType.home.defaultTitle)
    }

    /// Fetches the home feed as multiple named shelves (TYPE_ROW in Android).
    /// Returns one VideoGroup per shelf; each has layout == .row.
    /// Falls back to a single flat VideoGroup if no shelves are found.
    public func fetchHomeRows(continuationToken: String? = nil) async throws -> [VideoGroup] {
        let isAuth = authToken != nil
        var body = makeBody(
            client: isAuth ? tvClientContext : webClientContext,
            continuationToken: continuationToken,
            includeVisitorData: true)
        if continuationToken == nil {
            body["browseId"] = "FEwhat_to_watch"
        }
        let data =
            isAuth
            ? try await postTV(endpoint: "browse", body: body)
            : try await post(endpoint: "browse", body: body)
        updateVisitorData(from: data)
        let rows = parseVideoGroupRows(from: data)
        tubeLog.notice("fetchHomeRows → \(rows.count, privacy: .public) shelves")
        let rowShortsDetail = rows.map { row -> String in
            let s = row.videos.filter { $0.isShort }.count
            return "'\(row.title ?? "?")': \(s)/\(row.videos.count) shorts"
        }.joined(separator: ", ")
        tubeLog.notice("fetchHomeRows shelf detail: [\(rowShortsDetail, privacy: .public)]")
        return rows
    }

    // MARK: - Subscriptions

    /// Fetches subscriptions feed (requires auth).
    /// Uses TVHTML5 client on youtubei.googleapis.com — the only endpoint that accepts
    /// the OAuth token issued by the TV device-code flow.
    public func fetchSubscriptions(continuationToken: String? = nil) async throws -> VideoGroup {
        var body = makeBody(client: tvClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["browseId"] = "FEsubscriptions"
        }
        let data = try await postTV(endpoint: "browse", body: body)
        let group = try parseVideoGroup(from: data, title: L10n.string("Subscriptions"))
        // Preserve the API's arrival order — YouTube returns tiles in the order
        // it considers most relevant. Sorting by date re-inserts new pages'
        // videos between existing ones instead of appending them.
        return group
    }

    /// Fetches the list of channels the authenticated user subscribes to (requires auth).
    ///
    /// Strategy:
    ///  1. `/guide` endpoint with TV client + auth — returns the TV sidebar guide which
    ///     includes every subscribed channel with avatar thumbnail URLs via guideEntryRenderer.
    ///  2. If that yields no channels, fall back to parsing unique channels from the
    ///     TVHTML5 video-tile subscription feed (channel IDs + names, no avatars).
    public func fetchSubscribedChannels() async throws -> [Channel] {
        // Primary: TV guide sidebar — includes subscribed channels with avatar thumbnails
        let guideBody = makeBody(client: tvClientContext)
        let guideData = try await postTV(endpoint: "guide", body: guideBody)
        let guideKeys = Array(guideData.keys.sorted().prefix(8))
        tubeLog.notice("fetchSubscribedChannels guide top-level keys: \(guideKeys, privacy: .public)")
        let guideChannels = parseGuideChannels(from: guideData)
        tubeLog.notice("fetchSubscribedChannels guide → \(guideChannels.count, privacy: .public) channels")
        if !guideChannels.isEmpty { return guideChannels }

        // Fallback: TV subscription video-tile feed — extract unique channels (no avatars)
        tubeLog.notice("fetchSubscribedChannels: guide returned 0 — falling back to video tile parse")
        var tvBody = makeBody(client: tvClientContext)
        tvBody["browseId"] = "FEsubscriptions"
        let tvData = try await postTV(endpoint: "browse", body: tvBody)
        return parseSubscribedChannels(from: tvData)
    }

    /// Fetches watch history (requires auth).
    public func fetchHistory(continuationToken: String? = nil) async throws -> VideoGroup {
        var body = makeBody(client: tvClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["browseId"] = "FEhistory"
        }
        let data = try await postTV(endpoint: "browse", body: body)
        return try parseVideoGroup(from: data, title: L10n.string("History"))
    }

    // MARK: - Search

    public func search(
        query: String,
        continuationToken: String? = nil,
        filter: SearchFilter = .default
    ) async throws -> VideoGroup {
        var body = makeBody(client: webClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["query"] = query
            if let params = filter.encodedParams() {
                body["params"] = params
            }
        }
        let data = try await post(endpoint: "search", body: body)
        // DEBUG: dump raw search response for #shorts queries so we can inspect
        // which renderer types YouTube is actually returning.
        if query == "#shorts", let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        {
            let filename =
                continuationToken == nil
                ? "shorts_search_p1.json" : "shorts_search_cont_\(Int.random(in: 1000...9999)).json"
            let url = desktop.appendingPathComponent(filename)
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            {
                try? jsonData.write(to: url)
                tubeLog.notice(
                    "search DEBUG: dumped #shorts response (\(jsonData.count, privacy: .public) bytes) to Desktop/\(filename, privacy: .public)"
                )
            }
        }
        return try parseVideoGroup(from: data, title: L10n.string("Search: \(query)"))
    }

    public func fetchSearchSuggestions(query: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search")
        else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "youtube"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "callback", value: ""),
        ]
        guard let url = components.url else { return [] }
        print("[Suggestions] Fetching URL: \(url)")
        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[Suggestions] HTTP status: \(statusCode), bytes: \(data.count)")
        // Response format: [query, [[suggestion, 0, []], ...], ...]
        guard let raw = String(data: data, encoding: .utf8) else {
            print("[Suggestions] Failed to decode response as UTF-8")
            return []
        }
        print("[Suggestions] Raw prefix: \(raw.prefix(120))")
        // Extract the outermost JSON array — works regardless of callback wrapper name
        guard let arrayStart = raw.firstIndex(of: "["),
            let arrayEnd = raw.lastIndex(of: "]")
        else {
            print("[Suggestions] Could not find JSON array bounds")
            return []
        }
        let jsonString = String(raw[arrayStart...arrayEnd])
        print("[Suggestions] JSON prefix after strip: \(jsonString.prefix(120))")
        guard let jsonData = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [Any]
        else {
            print("[Suggestions] JSON parse failed")
            return []
        }
        guard let suggestions = json[safe: 1] as? [[Any]] else {
            print("[Suggestions] Unexpected JSON shape: \(json.prefix(2))")
            return []
        }
        let results = suggestions.compactMap { $0[safe: 0] as? String }
        print("[Suggestions] Parsed \(results.count) suggestions: \(results.prefix(5))")
        return results
    }

    // MARK: - Shorts

    public func fetchShorts() async throws -> VideoGroup {
        // NOTE (2026-05-24): Strategies 1–3 (FEshorts via postTV, postTVCategory, WEB)
        // were removed because YouTube deprecated the FEshorts browseId — all three
        // returned HTTP 400 on every client (TV+auth, TV-category, WEB). Confirmed via
        // log analysis: the home browse with the same token/version succeeds (200), so
        // it is specifically FEshorts that YouTube no longer accepts, not a client version
        // or auth issue. yt-dlp (2026.03.17) does not use FEshorts at all and does not
        // support the Shorts homepage feed. Search is the only working path right now.
        // TODO: re-add a FEshorts attempt if YouTube re-enables it, or find a replacement
        // browseId/params that yields a Shorts feed.

        // Search "#shorts" with the YouTube Shorts duration filter (EgIYAQ== / sp=EgIYAQ%3D%3D).
        // WEB client videoRenderer items in search results rarely carry reelWatchEndpoint or
        // the SHORTS overlay style, so parseVideoRenderer leaves isShort=false for most of them
        // even though they are genuine Shorts. Since the duration:short filter guarantees
        // every result is ≤ 4 min and we searched for "#shorts", we treat any video ≤ 180 s
        // as a Short and override isShort in-place.
        let shortsFilter = SearchFilter(duration: .short)
        let searchGroup = try await search(query: "#shorts", filter: shortsFilter)
        // Accept videos already flagged isShort=true by the parser (shortsLockupViewModel sets
        // isShort=true directly), OR any video with duration ≤ 180 s that wasn't flagged.
        // Do NOT reject on nil duration — shortsLockupViewModel items have nil duration.
        var shorts = searchGroup.videos.filter { $0.isShort || ($0.duration.map { $0 <= 180 } ?? false) }
        for i in shorts.indices where !shorts[i].isShort { shorts[i].isShort = true }
        let dropped = searchGroup.videos.filter { !($0.isShort || ($0.duration.map { $0 <= 180 } ?? false)) }
        for v in dropped {
            tubeLog.notice(
                "fetchShorts DROPPED: id=\(v.id, privacy: .public) dur=\(v.duration.map { "\($0)" } ?? "nil", privacy: .public) isShort=\(v.isShort, privacy: .public) title=\(v.title.prefix(40), privacy: .public)"
            )
        }
        tubeLog.notice(
            "fetchShorts search → \(searchGroup.videos.count, privacy: .public) total, \(shorts.count, privacy: .public) kept as shorts (\(dropped.count, privacy: .public) dropped), token=\(searchGroup.nextPageToken.map { String($0.prefix(16)) + "\u{2026}" } ?? "nil", privacy: .public)"
        )
        // Tag token with "srch:" so fetchShortsMore() uses only the search continuation path.
        return VideoGroup(
            title: L10n.string("Shorts"), videos: shorts, nextPageToken: searchGroup.nextPageToken.map { "srch:" + $0 })
    }

    public func fetchShortsMore(continuationToken: String) async throws -> VideoGroup {
        // InnerTube continuation tokens are client-specific: a token issued by one
        // client (e.g. postTV) returns HTTP 400 when sent to a different client
        // (e.g. WEB). fetchShorts() embeds a source prefix in every token it returns
        // so we can route the continuation to the correct client without retrying all.
        //
        // Prefix  Client         Auth needed
        // "stv:"  postTV         yes (Bearer)
        // "stvc:" postTVCategory no
        // "web:"  WEB browse     no
        // "srch:" search         no
        // ""      legacy         try-all (backward compat)
        let (source, rawToken): (String, String) = {
            let tagged: [(String, String)] = [
                ("stv:", "stv"), ("stvc:", "stvc"), ("web:", "web"), ("srch:", "srch"),
            ]
            for (prefix, tag) in tagged where continuationToken.hasPrefix(prefix) {
                return (tag, String(continuationToken.dropFirst(prefix.count)))
            }
            return ("", continuationToken)
        }()
        tubeLog.notice(
            "fetchShortsMore source=\(source.isEmpty ? "legacy" : source, privacy: .public) token=\(rawToken.prefix(16), privacy: .public)…"
        )
        let isAuth = authToken != nil

        switch source {
        case "stv":
            let body = makeBody(client: tvClientContext, continuationToken: rawToken)
            let data = try await postTV(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
            let shorts = group.videos.filter { $0.isShort }
            tubeLog.notice(
                "fetchShortsMore postTV → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts"
            )
            return VideoGroup(
                title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken.map { "stv:" + $0 })

        case "stvc":
            let body = makeBody(client: tvClientContext, continuationToken: rawToken)
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
            let shorts = group.videos.filter { $0.isShort }
            tubeLog.notice(
                "fetchShortsMore postTVCategory → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts"
            )
            return VideoGroup(
                title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken.map { "stvc:" + $0 })

        case "web":
            let body = makeBody(client: webClientContext, continuationToken: rawToken)
            let data = try await post(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
            let shorts = group.videos.filter { $0.isShort }
            tubeLog.notice(
                "fetchShortsMore WEB → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts"
            )
            return VideoGroup(
                title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken.map { "web:" + $0 })

        case "srch":
            let group = try await search(query: "#shorts", continuationToken: rawToken)
            var shorts = group.videos.filter { $0.isShort || ($0.duration.map { $0 <= 180 } ?? false) }
            for i in shorts.indices where !shorts[i].isShort { shorts[i].isShort = true }
            let dropped = group.videos.filter { !($0.isShort || ($0.duration.map { $0 <= 180 } ?? false)) }
            for v in dropped {
                tubeLog.notice(
                    "fetchShortsMore DROPPED: id=\(v.id, privacy: .public) dur=\(v.duration.map { "\($0)" } ?? "nil", privacy: .public) isShort=\(v.isShort, privacy: .public) title=\(v.title.prefix(40), privacy: .public)"
                )
            }
            tubeLog.notice(
                "fetchShortsMore search → \(group.videos.count, privacy: .public) total, \(shorts.count, privacy: .public) kept (\(dropped.count, privacy: .public) dropped), nextToken=\(group.nextPageToken != nil ? "yes" : "no", privacy: .public)"
            )
            return VideoGroup(
                title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken.map { "srch:" + $0 })

        default:
            // Legacy un-prefixed token (from older app versions): try all clients as before.
            if isAuth {
                do {
                    let body = makeBody(client: tvClientContext, continuationToken: rawToken)
                    let data = try await postTV(endpoint: "browse", body: body)
                    let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
                    let shorts = group.videos.filter { $0.isShort }
                    let token = group.nextPageToken.map { String($0.prefix(16)) + "…" } ?? "nil"
                    tubeLog.notice(
                        "fetchShortsMore postTV → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts, token=\(token, privacy: .public)"
                    )
                    if !group.videos.isEmpty {
                        return VideoGroup(
                            title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken)
                    }
                } catch {
                    tubeLog.notice("fetchShortsMore postTV failed (\(error, privacy: .public)) — trying postTVCategory")
                }
            }

            do {
                let body = makeBody(client: tvClientContext, continuationToken: rawToken)
                let data = try await postTVCategory(endpoint: "browse", body: body)
                let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
                let shorts = group.videos.filter { $0.isShort }
                let token = group.nextPageToken.map { String($0.prefix(16)) + "…" } ?? "nil"
                tubeLog.notice(
                    "fetchShortsMore postTVCategory → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts, token=\(token, privacy: .public)"
                )
                if !group.videos.isEmpty {
                    return VideoGroup(title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken)
                }
            } catch {
                tubeLog.notice("fetchShortsMore postTVCategory failed (\(error, privacy: .public)) — trying WEB")
            }

            do {
                let body = makeBody(client: webClientContext, continuationToken: rawToken)
                let data = try await post(endpoint: "browse", body: body)
                let group = try parseVideoGroup(from: data, title: L10n.string("Shorts"))
                let shorts = group.videos.filter { $0.isShort }
                let token = group.nextPageToken.map { String($0.prefix(16)) + "\u{2026}" } ?? "nil"
                tubeLog.notice(
                    "fetchShortsMore WEB → \(group.videos.count, privacy: .public) videos, \(shorts.count, privacy: .public) shorts, token=\(token, privacy: .public)"
                )
                if !group.videos.isEmpty {
                    return VideoGroup(title: L10n.string("Shorts"), videos: shorts, nextPageToken: group.nextPageToken)
                }
            } catch {
                tubeLog.notice("fetchShortsMore WEB failed (\(error, privacy: .public)) — trying search continuation")
            }

            // Last resort: search continuation token.
            let searchGroup = try await search(query: "#shorts", continuationToken: rawToken)
            let searchShorts = searchGroup.videos.filter { $0.isShort }
            let searchToken = searchGroup.nextPageToken.map { String($0.prefix(16)) + "\u{2026}" } ?? "nil"
            tubeLog.notice(
                "fetchShortsMore search → \(searchGroup.videos.count, privacy: .public) total, \(searchShorts.count, privacy: .public) shorts, token=\(searchToken, privacy: .public)"
            )
            return VideoGroup(
                title: L10n.string("Shorts"), videos: searchShorts, nextPageToken: searchGroup.nextPageToken)
        }
    }

    // MARK: - Category sections

    public func fetchMusic() async throws -> VideoGroup {
        do {
            // FEmusic_home is the TVHTML5 browse ID for the music category page.
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEmusic_home"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Music"))
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchMusic browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "music")
    }

    public func fetchGaming() async throws -> VideoGroup {
        do {
            // FEgaming requires TVHTML5 context on www.youtube.com (not googleapis.com).
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEgaming"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Gaming"))
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchGaming browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "gaming")
    }

    public func fetchNews() async throws -> VideoGroup {
        // FEnews is not a valid InnerTube browse ID — use search directly.
        return try await search(query: "news today")
    }

    public func fetchLive() async throws -> VideoGroup {
        do {
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FElive_home"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Live"))
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchLive browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "live stream")
    }

    public func fetchSports() async throws -> VideoGroup {
        do {
            // FEsportsau is the known TVHTML5 browse ID for the sports category.
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEsportsau"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: L10n.string("Sports"))
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchSports browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "sports")
    }
}
