import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - AuthenticatedTrackingURLsTests
//
// #51/#78 watch-history series. YouTube records a watch only when the stats pings carry
// the `ei`/`vm`/`of` that an *authenticated* player response minted. Earlier attempts
// asked the TV client on googleapis.com (no `playbackTracking`), then the WEB client on
// www.youtube.com (HTTP 400: it rejects the TV Bearer token), then fell back to the
// unauthenticated iOS response's URLs, which are bound to an anonymous visitor: their
// pings get HTTP 200 and are never recorded.
//
// Android (MediaServiceCore `FormatInfoWrapper.syncWithAuthInfoIfNeeded` →
// `VideoInfoService.getAuthVideoInfo`) asks the TVHTML5 client on www.youtube.com with
// the Bearer token and the session's `cpn`, and pings with the same Bearer/TV identity.
// These tests pin that request shape and the tracker's lazy resolution.

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]
    /// Captured request bodies keyed by URL substring match — lets tests inspect
    /// what was actually sent without crossing the actor boundary with a raw
    /// [String: Any] (which isn't Sendable).
    nonisolated(unsafe) static var capturedBodies: [String: Data] = [:]
    /// Captured request URLs keyed by URL substring match — primary key for
    /// the "endpoint goes to www.youtube.com" assertions.
    nonisolated(unsafe) static var capturedURLs: [String: URL] = [:]
    /// Captured request headers keyed by URL substring match.
    nonisolated(unsafe) static var capturedHeaders: [String: [String: String]] = [:]
    /// Number of requests per URL substring match.
    nonisolated(unsafe) static var requestCounts: [String: Int] = [:]
    /// Every request URL in the order it was sent.
    nonisolated(unsafe) static var requestLog: [URL] = []

    static func reset(responses: [String: (statusCode: Int, body: Data)]) {
        self.responses = responses
        capturedBodies = [:]
        capturedURLs = [:]
        capturedHeaders = [:]
        requestCounts = [:]
        requestLog = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        if let requestURL = request.url { Self.requestLog.append(requestURL) }
        for key in Self.responses.keys where url.contains(key) {
            if let body = request.httpBodyOrAccumulated() {
                Self.capturedBodies[key] = body
            }
            Self.capturedURLs[key] = request.url
            Self.capturedHeaders[key] = request.allHTTPHeaderFields ?? [:]
            Self.requestCounts[key, default: 0] += 1
        }
        let match = Self.responses.filter { url.contains($0.key) }.max(by: { $0.key.count < $1.key.count })
        let (statusCode, body) = match.map { ($0.value.statusCode, $0.value.body) } ?? (200, Data("{}".utf8))
        let httpResponse = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// `httpBody` is nil for requests created via `URLSession`'s body-from-Data
    /// path in some configurations; `httpBodyStream` is the alternate path.
    /// Try both so the captured body is reliable across delegate/protocol setups.
    func httpBodyOrAccumulated() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}

@Suite("Authenticated tracking URLs — TV client on www.youtube.com (#51/#78)", .serialized)
struct AuthenticatedTrackingURLsTests {

    private static let wwwPlayer = "www.youtube.com/youtubei/v1/player"
    private static let googleapisPlayer = "googleapis.com/youtubei/v1/player"
    private static let stsPage = "youtube.com/"

    private func makeAPI(authToken: String? = "fake-token") -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: authToken, session: session)
    }

    private static func playerResponse(trackingQuery: String?) -> Data {
        var response: [String: Any] = [
            "videoDetails": ["videoId": "testvid123"],
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["formats": [], "adaptiveFormats": []],
        ]
        if let trackingQuery {
            response["playbackTracking"] = [
                "videostatsPlaybackUrl": [
                    "baseUrl": "https://s.youtube.com/api/stats/playback?ns=yt&c=TVHTML5&\(trackingQuery)"
                ],
                "videostatsWatchtimeUrl": [
                    "baseUrl": "https://s.youtube.com/api/stats/watchtime?ns=yt&c=TVHTML5&\(trackingQuery)"
                ],
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }

    private static func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    // MARK: - fetchHistoryTrackingURLs

    @Test("history tracking request is Android's authenticated TV_DOWNGRADED /player on www.youtube.com")
    func historyRequestMatchesAndroid() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: "ei=E&vm=V&of=O")),
        ])
        _ = await makeAPI().fetchHistoryTrackingURLs(videoId: "testvid123", cpn: "CPN123")

        guard let url = StubURLProtocol.capturedURLs[Self.wwwPlayer],
            let headers = StubURLProtocol.capturedHeaders[Self.wwwPlayer],
            let body = Self.json(StubURLProtocol.capturedBodies[Self.wwwPlayer])
        else {
            Issue.record("No /player request captured on www.youtube.com")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!query.contains { $0.name == "key" }, "Bearer requests carry no API key")
        #expect(headers["Authorization"] == "Bearer fake-token")
        #expect(headers["X-YouTube-Client-Name"] == InnerTubeClients.TV.nameID)
        // The 7.x client answers UNPLAYABLE without a living-room BotGuard poToken; the
        // downgraded 5.x client with the old Cobalt UA needs none (Android TV_DOWNGRADED).
        #expect(headers["X-YouTube-Client-Version"] == InnerTubeClients.TVDowngraded.version)
        #expect(headers["User-Agent"] == InnerTubeClients.TVDowngraded.userAgent)
        #expect(headers["Referer"] == InnerTubeClients.TV.referer)
        let client = (body["context"] as? [String: Any])?["client"] as? [String: Any]
        #expect(client?["clientName"] as? String == InnerTubeClients.TV.name)
        #expect(client?["clientVersion"] as? String == InnerTubeClients.TVDowngraded.version)
        #expect(client?["userAgent"] as? String == InnerTubeClients.TVDowngraded.userAgent)
        #expect(client?["clientScreen"] as? String == "WATCH")
        #expect(body["serviceIntegrityDimensions"] == nil, "TV_DOWNGRADED sends no poToken")
        #expect(body["videoId"] as? String == "testvid123")
        #expect(body["cpn"] as? String == "CPN123", "The pings reuse this cpn, so the request must carry it")
        let cpbc = (body["playbackContext"] as? [String: Any])?["contentPlaybackContext"] as? [String: Any]
        #expect(cpbc?["html5Preference"] as? String == "HTML5_PREF_WANTS")
        #expect(StubURLProtocol.requestCounts[Self.googleapisPlayer] == nil, "No fallback when www answers")
    }

    @Test("returns the account-bound URLs when the response carries ei/vm/of")
    func extractsAccountBoundURLs() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: "ei=E&vm=V&of=O")),
        ])
        let urls = await makeAPI().fetchHistoryTrackingURLs(videoId: "testvid123", cpn: "CPN123")
        #expect(InnerTubeAPI.trackingSession(from: urls)?.eventId == "E")
    }

    @Test("falls back to the googleapis.com TV host when www.youtube.com has no tracking data")
    func fallsBackToGoogleapisHost() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (400, Data("{}".utf8)),
            Self.googleapisPlayer: (200, Self.playerResponse(trackingQuery: "ei=G&vm=V&of=O")),
        ])
        let urls = await makeAPI().fetchHistoryTrackingURLs(videoId: "testvid123", cpn: "CPN123")
        #expect(InnerTubeAPI.trackingSession(from: urls)?.eventId == "G")
        #expect(StubURLProtocol.capturedHeaders[Self.googleapisPlayer]?["Authorization"] == "Bearer fake-token")
    }

    @Test("URLs without ei/vm/of are rejected — their pings would never be recorded")
    func rejectsURLsWithoutSessionParams() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: "vm=V&of=O")),
            Self.googleapisPlayer: (200, Self.playerResponse(trackingQuery: nil)),
        ])
        let urls = await makeAPI().fetchHistoryTrackingURLs(videoId: "testvid123", cpn: "CPN123")
        #expect(urls == nil)
    }

    @Test("signed out: no request, no URLs")
    func returnsNilWithoutAuth() async {
        StubURLProtocol.reset(responses: [Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: "ei=E&vm=V&of=O"))])
        let urls = await makeAPI(authToken: nil).fetchHistoryTrackingURLs(videoId: "testvid123", cpn: "CPN123")
        #expect(urls == nil)
        #expect(StubURLProtocol.requestCounts[Self.wwwPlayer] == nil)
    }

    // MARK: - Stats pings

    @Test("stats pings use the Bearer token and TV identity, even when a SAPISID is set")
    func statsPingsUseTVIdentity() async {
        StubURLProtocol.reset(responses: ["api/stats/watchtime": (200, Data())])
        let api = makeAPI()
        await api.setSAPISID("test-sapisid-cookie-value")
        let bound = URL(string: "https://s.youtube.com/api/stats/watchtime?ei=E&vm=V&of=O")!
        await api.reportWatchtime(
            videoId: "testvid123", cpn: "CPN123",
            trackingURLs: PlaybackTrackingURLs(playbackURL: bound, watchtimeURL: bound),
            lengthSeconds: 100, segmentStart: 0, segmentEnd: 10)

        let headers = StubURLProtocol.capturedHeaders["api/stats/watchtime"]
        #expect(headers?["Authorization"] == "Bearer fake-token")
        #expect(headers?["User-Agent"] == InnerTubeClients.TV.userAgent)
        #expect(headers?["Referer"] == InnerTubeClients.TV.referer)
    }

    // MARK: - WatchtimeTracker lazy resolution

    @MainActor
    @Test("the first checkpoint resolves account-bound URLs and pings with the session cpn")
    func trackerResolvesOnFirstCheckpoint() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: "ei=EI_AUTH&vm=V&of=O")),
            "api/stats/playback": (200, Data()),
            "api/stats/watchtime": (200, Data()),
        ])
        let tracker = WatchtimeTracker(api: makeAPI())
        _ = tracker.transition(to: "resolvevid-\(UUID().uuidString)", cpn: "CPN-A", flushPosition: 0, flushDuration: 0)
        await tracker.checkpoint(position: 10, duration: 1000)

        #expect(tracker.hasTrackingSession)
        #expect(Self.json(StubURLProtocol.capturedBodies[Self.wwwPlayer])?["cpn"] as? String == "CPN-A")
        guard let ping = StubURLProtocol.capturedURLs["api/stats/watchtime"] else {
            Issue.record("No watchtime ping sent")
            return
        }
        let items = URLComponents(url: ping, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "ei" }?.value == "EI_AUTH")
        #expect(items.first { $0.name == "cpn" }?.value == "CPN-A")
        #expect(StubURLProtocol.requestCounts["api/stats/playback"] == 1)
    }

    @MainActor
    @Test("without account-bound URLs nothing is pinged, and a failure is not retried per checkpoint")
    func trackerSkipsPingsAndBacksOffWhenUnresolved() async {
        StubURLProtocol.reset(responses: [
            Self.stsPage: (200, Data("\"STS\":12345".utf8)),
            Self.wwwPlayer: (200, Self.playerResponse(trackingQuery: nil)),
            Self.googleapisPlayer: (200, Self.playerResponse(trackingQuery: nil)),
            "api/stats/": (200, Data()),
        ])
        let tracker = WatchtimeTracker(api: makeAPI())
        _ = tracker.transition(to: "unresolved-\(UUID().uuidString)", cpn: "CPN-B", flushPosition: 0, flushDuration: 0)
        await tracker.checkpoint(position: 10, duration: 1000)
        await tracker.checkpoint(position: 40, duration: 1000)

        #expect(!tracker.hasTrackingSession)
        #expect(StubURLProtocol.requestCounts["api/stats/"] == nil)
        #expect(StubURLProtocol.requestCounts[Self.wwwPlayer] == 1)
    }

    /// Stats pings in send order, as (path suffix, query items).
    private static func statsPings() -> [(kind: String, items: [URLQueryItem])] {
        StubURLProtocol.requestLog.compactMap { url in
            guard url.path.hasPrefix("/api/stats/") else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return (url.lastPathComponent, items)
        }
    }

    private static let failingResolution: [String: (statusCode: Int, body: Data)] = [
        stsPage: (200, Data("\"STS\":12345".utf8)),
        wwwPlayer: (200, playerResponse(trackingQuery: nil)),
        googleapisPlayer: (200, playerResponse(trackingQuery: nil)),
        "api/stats/": (200, Data()),
    ]

    private static let succeedingResolution: [String: (statusCode: Int, body: Data)] = [
        stsPage: (200, Data("\"STS\":12345".utf8)),
        wwwPlayer: (200, playerResponse(trackingQuery: "ei=EI_LATE&vm=V&of=O")),
        "api/stats/": (200, Data()),
    ]

    @MainActor
    @Test("after a failed resolution, the recovered session opens the record before reporting watchtime")
    func trackerRecoversWithPlaybackBeforeWatchtime() async {
        StubURLProtocol.reset(responses: Self.failingResolution)
        let tracker = WatchtimeTracker(api: makeAPI())
        let videoId = "recover-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "CPN-R", flushPosition: 0, flushDuration: 0)
        await tracker.checkpoint(position: 10, duration: 1000)
        #expect(!tracker.hasTrackingSession)

        // A later resolution succeeds (setTrackingURLs(nil) clears the back-off, as a token
        // refresh does; the 5-minute retry takes the same path).
        StubURLProtocol.reset(responses: Self.succeedingResolution)
        tracker.setTrackingURLs(nil)
        await tracker.checkpoint(position: 40, duration: 1000)

        let pings = Self.statsPings()
        #expect(pings.map(\.kind) == ["playback", "watchtime"], "YouTube ignores watchtime without a playback ping")
        let watchtime = pings.last?.items ?? []
        #expect(watchtime.first { $0.name == "ei" }?.value == "EI_LATE")
        #expect(watchtime.first { $0.name == "st" }?.value == "0.000", "The failed checkpoint must not consume the segment")
        await VideoStateStore.shared.clear(videoId: videoId)
    }

    @MainActor
    @Test("a final checkpoint without tracking URLs leaves final=1 to the session flush")
    func unresolvedFinalCheckpointIsReportedByFlush() async {
        StubURLProtocol.reset(responses: Self.failingResolution)
        let tracker = WatchtimeTracker(api: makeAPI())
        let videoId = "final-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "CPN-F", flushPosition: 0, flushDuration: 0)
        await tracker.checkpoint(position: 990, duration: 1000)
        #expect(Self.statsPings().isEmpty)

        StubURLProtocol.reset(responses: Self.succeedingResolution)
        let flush = tracker.transition(to: "next-\(UUID().uuidString)", cpn: "CPN-N", flushPosition: 995, flushDuration: 1000)
        await flush()

        let pings = Self.statsPings()
        #expect(pings.map(\.kind) == ["playback", "watchtime"])
        #expect(pings.allSatisfy { ping in ping.items.contains { $0.name == "final" && $0.value == "1" } })
        await VideoStateStore.shared.clear(videoId: videoId)
    }

    @Test("WebSafari playback fetch never sends Bearer (www.youtube.com rejects it; PR #129)")
    func playbackFetchOmitsBearerWithoutSAPISID() async {
        StubURLProtocol.responses = [
            "youtube.com/": (200, Data("\"STS\":12345".utf8)),
            "youtubei/v1/player": (200, Data("{}".utf8)),
        ]
        StubURLProtocol.capturedHeaders = [:]
        let api = makeAPI()
        _ = try? await api.fetchPlayerInfoWebSafari(videoId: "testvid123")

        guard let headers = StubURLProtocol.capturedHeaders["youtubei/v1/player"] else {
            Issue.record("No request headers captured for /player")
            return
        }
        #expect(headers["Authorization"] == nil)
    }

    // MARK: - Stats URL construction (Android parity)

    private static func session() -> InnerTubeAPI.TrackingSession {
        InnerTubeAPI.TrackingSession(
            eventId: "EVENT", visitorMonitoring: "VM", ofParam: "OF", playlistId: nil)
    }

    @Test("stats pings are rebuilt against www.youtube.com")
    func statsURLUsesWWWHost() {
        // The server-supplied baseUrl often points at s.youtube.com, which is not the
        // host YouTube attributes authenticated pings on (Android rebuilds it too).
        let url = InnerTubeAPI.statsURLForTesting("watchtime", session: Self.session(), params: ["docid": "abc123"])
        #expect(url?.host == "www.youtube.com", "Stats ping must target www.youtube.com. Actual: \(url?.host ?? "nil")")
        #expect(url?.path == "/api/stats/watchtime")
    }

    @Test("stats pings carry ns, ver and the ei/vm/of session params")
    func statsURLCarriesSessionParams() {
        let url = InnerTubeAPI.statsURLForTesting("playback", session: Self.session(), params: ["docid": "abc123"])
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("ns") == "yt")
        #expect(value("ver") == "2")
        #expect(value("ei") == "EVENT")
        #expect(value("vm") == "VM")
        #expect(value("of") == "OF")
        #expect(value("docid") == "abc123")
    }

    @Test("tracking session is only derived when ei, vm and of are all present")
    func trackingSessionRequiresAllParams() {
        func urls(_ query: String) -> PlaybackTrackingURLs {
            PlaybackTrackingURLs(
                playbackURL: URL(string: "https://s.youtube.com/api/stats/playback?\(query)")!,
                watchtimeURL: URL(string: "https://s.youtube.com/api/stats/watchtime?\(query)")!)
        }
        #expect(InnerTubeAPI.trackingSession(from: urls("ei=E&vm=V&of=O")) != nil)
        #expect(InnerTubeAPI.trackingSession(from: urls("ei=E&vm=V")) == nil, "Missing of must bail out")
        #expect(InnerTubeAPI.trackingSession(from: urls("vm=V&of=O")) == nil, "Missing ei must bail out")
        #expect(InnerTubeAPI.trackingSession(from: urls("ei=E&vm=&of=O")) == nil, "Empty vm must bail out")
        #expect(InnerTubeAPI.trackingSession(from: nil) == nil)
    }

    @Test("playlist id is forwarded when the tracking URL carries one")
    func trackingSessionForwardsPlaylistId() {
        let urls = PlaybackTrackingURLs(
            playbackURL: URL(string: "https://s.youtube.com/api/stats/playback?ei=E&vm=V&of=O&plid=PL1")!,
            watchtimeURL: URL(string: "https://s.youtube.com/api/stats/watchtime?ei=E&vm=V&of=O&plid=PL1")!)
        #expect(InnerTubeAPI.trackingSession(from: urls)?.playlistId == "PL1")
    }

    @Test("durations are formatted with millisecond precision")
    func secondsAreFormattedLikeAndroid() {
        #expect(InnerTubeAPI.formatSeconds(119.4053) == "119.405")
        #expect(InnerTubeAPI.formatSeconds(0) == "0.000")
        #expect(InnerTubeAPI.formatSeconds(-5) == "0.000", "Negative positions must clamp to zero")
    }
}
