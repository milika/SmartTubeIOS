import Foundation
import Testing

@testable import SmartTubeIOSCore

// Races between WatchtimeTracker's lazy tracking-URL resolution (the first checkpoint awaits
// an authenticated /player request) and things that happen while that request is in flight:
// the app exiting, the account changing, the same video being reopened.
//
// The /player request is held open by `GatedHistoryProtocol` until the test releases it,
// so every interleaving is deterministic (no sleeps, no live network).

private final class GatedHistoryProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: GatedHistoryProtocol?
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var blocking = true
    nonisolated(unsafe) private static var startWaiter: CheckedContinuation<Void, Never>?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() {
        lock.withLock {
            pending = nil
            started = false
            blocking = true
            startWaiter = nil
            requests = []
        }
    }

    static func capturedRequests() -> [URLRequest] { lock.withLock { requests } }

    /// Suspends until the first /player request is being held.
    static func waitForPlayerRequest() async {
        await withCheckedContinuation { continuation in
            let alreadyStarted = lock.withLock {
                if started { return true }
                startWaiter = continuation
                return false
            }
            if alreadyStarted { continuation.resume() }
        }
    }

    /// Answers the held /player request with `ei=EI_OLD`; later ones answer immediately.
    static func releasePlayerResponse() {
        let held = lock.withLock {
            blocking = false
            let value = pending
            pending = nil
            return value
        }
        held?.respond(eventId: "EI_OLD")
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isPlayer = request.url?.path == "/youtubei/v1/player"
        let (shouldBlock, waiter) = Self.lock.withLock {
            Self.requests.append(request)
            guard isPlayer, Self.blocking else {
                return (false, nil as CheckedContinuation<Void, Never>?)
            }
            Self.pending = self
            Self.started = true
            let waiter = Self.startWaiter
            Self.startWaiter = nil
            return (true, waiter)
        }
        waiter?.resume()
        if !shouldBlock { respond(eventId: "EI_FRESH") }
    }

    private func respond(eventId: String) {
        var body = Data()
        if request.url?.path == "/youtubei/v1/player" {
            let query = "ei=\(eventId)&vm=V&of=O"
            body =
                (try? JSONSerialization.data(withJSONObject: [
                    "playbackTracking": [
                        "videostatsPlaybackUrl": ["baseUrl": "https://s.youtube.com/api/stats/playback?\(query)"],
                        "videostatsWatchtimeUrl": ["baseUrl": "https://s.youtube.com/api/stats/watchtime?\(query)"],
                    ]
                ])) ?? Data()
        }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension InnerTubeAPI {
    /// Pre-seeds STS and visitorData so the history request is a single /player call.
    fileprivate func seedForHistoryRequest() {
        signatureTimestamp = 12345
        signatureTimestampFetchedAt = Date()
        visitorData = "TEST_VISITOR"
    }
}

@MainActor
@Suite("WatchtimeTracker – tracking resolution races", .serialized)
struct WatchtimeTrackerResolutionRaceTests {
    private func makeTracker() async -> (InnerTubeAPI, WatchtimeTracker) {
        GatedHistoryProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedHistoryProtocol.self]
        let api = InnerTubeAPI(authToken: "old-account-token", session: URLSession(configuration: configuration))
        await api.seedForHistoryRequest()
        return (api, WatchtimeTracker(api: api))
    }

    @Test("local resume progress is saved while the history resolution is pending")
    func localProgressDoesNotWaitForTrackingRequest() async {
        let (_, tracker) = await makeTracker()
        let videoId = "race-local-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "CPN-A", flushPosition: 0, flushDuration: 0)
        let checkpoint = Task { await tracker.checkpoint(position: 42, duration: 1000) }
        await GatedHistoryProtocol.waitForPlayerRequest()

        let savedWhileRequestIsPending = await VideoStateStore.shared.state(for: videoId)
        #expect(savedWhileRequestIsPending?.position == 42)

        GatedHistoryProtocol.releasePlayerResponse()
        await checkpoint.value
        await VideoStateStore.shared.clear(videoId: videoId)
    }

    @Test("an account reset discards the previous account's in-flight resolution")
    func accountResetDiscardsInFlightURLs() async {
        let (api, tracker) = await makeTracker()
        let videoId = "race-auth-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "CPN-A", flushPosition: 0, flushDuration: 0)
        let checkpoint = Task { await tracker.checkpoint(position: 42, duration: 1000) }
        await GatedHistoryProtocol.waitForPlayerRequest()

        await api.setAuthToken("new-account-token")
        tracker.setTrackingURLs(nil)
        GatedHistoryProtocol.releasePlayerResponse()
        await checkpoint.value

        #expect(!tracker.hasTrackingSession)
        let stalePings = GatedHistoryProtocol.capturedRequests().filter {
            $0.url?.path.hasPrefix("/api/stats/") == true
                && $0.url?.query?.contains("ei=EI_OLD") == true
        }
        #expect(stalePings.isEmpty, "The old account's ei must never be sent with the new account's token")
        await VideoStateStore.shared.clear(videoId: videoId)
    }

    @Test("reopening the same video: a stale final checkpoint does not finish the new session")
    func sameVideoNewCPNDiscardsOldCheckpoint() async {
        let (_, tracker) = await makeTracker()
        let videoId = "race-session-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "CPN-A", flushPosition: 0, flushDuration: 0)
        let checkpoint = Task { await tracker.checkpoint(position: 990, duration: 1000) }
        await GatedHistoryProtocol.waitForPlayerRequest()

        _ = tracker.transition(to: videoId, cpn: "CPN-B", flushPosition: 0, flushDuration: 0)
        GatedHistoryProtocol.releasePlayerResponse()
        await checkpoint.value

        let bound = URL(string: "https://s.youtube.com/api/stats/watchtime?ei=EI_NEW&vm=V&of=O")!
        tracker.setTrackingURLs(PlaybackTrackingURLs(playbackURL: bound, watchtimeURL: bound))
        await tracker.checkpoint(position: 10, duration: 1000)

        let freshWatchtimePings = GatedHistoryProtocol.capturedRequests().filter {
            $0.url?.path == "/api/stats/watchtime" && $0.url?.query?.contains("cpn=CPN-B") == true
        }
        #expect(freshWatchtimePings.count == 1)
        let freshResumeState = await VideoStateStore.shared.state(for: videoId)
        #expect(freshResumeState?.position == 10)
        await VideoStateStore.shared.clear(videoId: videoId)
    }
}
