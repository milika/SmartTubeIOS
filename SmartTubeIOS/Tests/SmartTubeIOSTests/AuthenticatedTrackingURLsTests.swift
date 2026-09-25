import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - AuthenticatedTrackingURLsTests
//
// #51/#78 (and comment #4917617951) watch-history regression series.
//
// Three prior fixes all failed to credit the view to the user's history:
//   1. Auth propagation (commit 20a2b9f) — pings now carry the Bearer token.
//   2. Duration fix (commit f34477b) — checkpoint no longer skipped with dur=0.
//   3. Body shape (commit 8a28f97) — buildTrackingURLsBody mirrored
//      fetchPlayerInfoAuthenticated. Author flagged this fix as unverified live.
//
// Live retest by user Aiddog10 (GitHub comment 4917617951, 2026-07-08): still
// `usedFallback=true` and `no tracking data in TV player response` for every
// video. The body-shape hypothesis was a red herring.
//
// The actual root causes are at the transport layer, not the body layer:
//
// A. `fetchAuthenticatedTrackingURLs` was using `postTV` (googleapis.com TV
//    client). The googleapis.com InnerTube surface is a restricted API that
//    exposes streamingData/playabilityStatus/videoDetails but does NOT include
//    `playbackTracking` in the response. Switching to a www.youtube.com
//    endpoint (postWebSafari) — which is what the IFrame player and
//    youtube.com use — reliably returns playbackTracking.
//
// B. The stats pings reused the server-supplied `baseUrl`, which frequently
//    points at `s.youtube.com`. Android rebuilds every ping against
//    `https://www.youtube.com/api/stats/…` — that prefix is exactly what its
//    OkHttp interceptor matches when attaching the Bearer token and
//    X-Goog-Visitor-Id, so the rebuild is what makes a ping attributable at all.
//    Pings without `ei`/`vm`/`of` are now skipped instead of fired blindly.
//
// The auth context is already in place: AuthService.fetchYouTubeWebCookies()
// (called from AuthService+DeviceFlow.swift:71 after every sign-in) obtains
// the YouTube.com SAPISID cookie and stores it on the InnerTubeAPI actor
// via setSAPISID(). postWebSafari uses SAPISIDHASH auth when SAPISID is
// present, Bearer+AuthUser otherwise.

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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        for key in Self.responses.keys where url.contains(key) {
            if let body = request.httpBodyOrAccumulated() {
                Self.capturedBodies[key] = body
            }
            Self.capturedURLs[key] = request.url
            Self.capturedHeaders[key] = request.allHTTPHeaderFields ?? [:]
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

@Suite("Authenticated tracking URLs — endpoint + auth (#291)", .serialized)
struct AuthenticatedTrackingURLsTests {

    private func makeAPI(authToken: String? = "fake-token") -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: authToken, session: session)
    }

    // MARK: - Existing-shape tests (updated for new endpoint)

    @Test("the actual /player request body includes playbackContext.contentPlaybackContext")
    func requestBodyIncludesPlaybackContext() async {
        // The "youtubei/v1/player" key is intentionally longer than "youtube.com/" (12 chars)
        // so the stub dispatch picks the player response (not the STS homepage response) for
        // the actual /player request.
        StubURLProtocol.responses = [
            "youtube.com/": (200, Data("\"STS\":12345".utf8)),
            "youtubei/v1/player": (200, Data("{}".utf8)),
        ]
        StubURLProtocol.capturedBodies = [:]
        let api = makeAPI()
        _ = await api.fetchAuthenticatedTrackingURLs(videoId: "testvid123")

        guard let playerBodyData = StubURLProtocol.capturedBodies["youtubei/v1/player"],
            let body = try? JSONSerialization.jsonObject(with: playerBodyData) as? [String: Any]
        else {
            Issue.record("No request body captured for /player")
            return
        }
        let playbackContext = body["playbackContext"] as? [String: Any]
        let cpbc = playbackContext?["contentPlaybackContext"] as? [String: Any]
        #expect(
            cpbc != nil,
            "Body must include playbackContext.contentPlaybackContext — its absence is why playbackTracking never came back from YouTube"
        )
        #expect(cpbc?["html5Preference"] as? String == "HTML5_PREF_WANTS")
        #expect(body["videoId"] as? String == "testvid123")
    }

    @Test("fetchAuthenticatedTrackingURLs extracts URLs when playbackTracking is present")
    func extractsTrackingURLsWhenPresent() async {
        let playerResponse: [String: Any] = [
            "videoDetails": ["videoId": "testvid123"],
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["formats": [], "adaptiveFormats": []],
            "playbackTracking": [
                "videostatsPlaybackUrl": [
                    "baseUrl": "https://www.youtube.com/api/stats/playback?ns=yt&c=TVHTML5&cver=7.0&ver=2"
                ],
                "videostatsWatchtimeUrl": [
                    "baseUrl": "https://www.youtube.com/api/stats/watchtime?ns=yt&c=TVHTML5&cver=7.0&ver=2"
                ],
            ],
        ]
        let responseData = try! JSONSerialization.data(withJSONObject: playerResponse)
        StubURLProtocol.responses = [
            "youtube.com/": (200, Data("\"STS\":12345".utf8)),
            "youtubei/v1/player": (200, responseData),
        ]
        let api = makeAPI()
        let result = await api.fetchAuthenticatedTrackingURLs(videoId: "testvid123")

        #expect(result != nil, "Must extract tracking URLs from a response that includes playbackTracking")
        #expect(result?.playbackURL.absoluteString.contains("api/stats/playback") == true)
        #expect(result?.watchtimeURL.absoluteString.contains("api/stats/watchtime") == true)
    }

    @Test("fetchAuthenticatedTrackingURLs returns nil without an auth token or SAPISID")
    func returnsNilWithoutAuth() async {
        let api = makeAPI(authToken: nil)
        let result = await api.fetchAuthenticatedTrackingURLs(videoId: "testvid123")
        #expect(result == nil)
    }

    // MARK: - New tests for the actual fix (#291)

    @Test("fetchAuthenticatedTrackingURLs hits www.youtube.com, not googleapis.com")
    func fetchesFromWwwYouTube() async {
        // Red test for #291: the current implementation posts to youtubei.googleapis.com,
        // which does not return playbackTracking. The fix switches to www.youtube.com
        // (the same endpoint the IFrame player and youtube.com use), which does.
        StubURLProtocol.responses = [
            "youtube.com/": (200, Data("\"STS\":12345".utf8)),
            "youtubei/v1/player": (200, Data("{}".utf8)),
        ]
        StubURLProtocol.capturedURLs = [:]
        let api = makeAPI()
        _ = await api.fetchAuthenticatedTrackingURLs(videoId: "testvid123")

        guard let playerURL = StubURLProtocol.capturedURLs["youtubei/v1/player"] else {
            Issue.record("No request URL captured for /player")
            return
        }
        #expect(
            playerURL.host?.contains("www.youtube.com") == true,
            "Tracking-URLs fetch must hit www.youtube.com (where playbackTracking is returned), not youtubei.googleapis.com. Captured: \(playerURL.absoluteString)"
        )
    }

    @Test("fetchAuthenticatedTrackingURLs uses SAPISIDHASH auth when SAPISID is present")
    func usesSAPISIDHASHWhenSAPISIDPresent() async {
        // Red test for #291: the current implementation posts to googleapis.com with
        // Bearer auth; www.youtube.com rejects Bearer on the web client and requires
        // either SAPISIDHASH (when the YouTube web session cookie is available — which
        // fetchYouTubeWebCookies obtains after every sign-in) or Bearer+AuthUser as a
        // fallback. The web endpoint reliably returns playbackTracking in both auth
        // modes; SAPISIDHASH is the canonical "legitimate web session" mode.
        StubURLProtocol.responses = [
            "youtube.com/": (200, Data("\"STS\":12345".utf8)),
            "youtubei/v1/player": (200, Data("{}".utf8)),
        ]
        StubURLProtocol.capturedHeaders = [:]
        let api = makeAPI()
        await api.setSAPISID("test-sapisid-cookie-value")
        _ = await api.fetchAuthenticatedTrackingURLs(videoId: "testvid123")

        guard let playerHeaders = StubURLProtocol.capturedHeaders["youtubei/v1/player"] else {
            Issue.record("No request headers captured for /player")
            return
        }
        let auth = playerHeaders["Authorization"] ?? playerHeaders["authorization"]
        #expect(
            auth?.hasPrefix("SAPISIDHASH ") == true,
            "With SAPISID set, request must use SAPISIDHASH Authorization (the only auth scheme www.youtube.com accepts for web-client nameIDs). Captured Authorization: \(auth ?? "<none>")"
        )
        // The X-Origin header is required for SAPISIDHASH auth (per postWebSafari's existing wiring).
        #expect(
            playerHeaders["X-Origin"] == "1",
            "SAPISIDHASH auth requires X-Origin: 1 (set by postWebSafari). Captured headers: \(playerHeaders.keys.sorted())"
        )
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
