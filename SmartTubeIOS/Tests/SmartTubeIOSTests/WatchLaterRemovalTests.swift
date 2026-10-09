import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchLaterRemovalTests (#122)
//
// removeFromWatchLater currently sends `{"action": "ACTION_REMOVE_VIDEO", "removedVideoId": videoId}`
// to browse/edit_playlist. InnerTube's ACTION_REMOVE_VIDEO requires `setVideoId` — a per-playlist-item
// token distinct from the raw video ID (a playlist can hold the same video more than once, so removal
// is keyed by playlist entry, not by video). Sending `removedVideoId` there is rejected/ignored by the
// API, which is exactly the reported "can't remove from Watch Later" symptom.
//
// The `setVideoId` token is only obtainable from a playlistVideoRenderer's own JSON when *listing*
// the playlist — it is not derivable from the video ID alone. So this fix has two parts:
//   1. Video model gains `setVideoId`, and parsePlaylistVideoRenderer extracts it.
//   2. removeFromWatchLater takes that setVideoId (not the raw videoId) and sends it correctly.

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]
    nonisolated(unsafe) static var capturedBodies: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        for key in Self.responses.keys where url.contains(key) {
            if let body = request.httpBodyOrAccumulated() {
                Self.capturedBodies[key] = body
            }
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

extension URLRequest {
    fileprivate func httpBodyOrAccumulated() -> Data? {
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

@Suite("Watch Later removal — correct InnerTube action shape (#122)", .serialized)
struct WatchLaterRemovalTests {

    private func makeAPI() -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: "fake-token", session: session)
    }

    @Test("removeFromWatchLater sends setVideoId, not removedVideoId")
    func removeFromWatchLaterSendsSetVideoId() async throws {
        StubURLProtocol.responses = ["browse/edit_playlist": (200, Data("{}".utf8))]
        StubURLProtocol.capturedBodies = [:]
        let api = makeAPI()
        try await api.removeFromWatchLater(setVideoId: "PL_SET_VIDEO_TOKEN_1")

        guard let bodyData = StubURLProtocol.capturedBodies["browse/edit_playlist"],
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let actions = body["actions"] as? [[String: Any]],
            let action = actions.first
        else {
            Issue.record("No request body captured for browse/edit_playlist")
            return
        }
        #expect(action["action"] as? String == "ACTION_REMOVE_VIDEO")
        #expect(
            action["setVideoId"] as? String == "PL_SET_VIDEO_TOKEN_1",
            "ACTION_REMOVE_VIDEO must carry setVideoId (the playlist-entry token), not the raw video ID — sending removedVideoId here is why removal silently fails. Actual action: \(action)"
        )
        #expect(
            action["removedVideoId"] == nil,
            "removedVideoId is not a field ACTION_REMOVE_VIDEO recognizes — its presence means the old, broken shape is still being sent."
        )
        #expect(body["playlistId"] as? String == "WL")
    }

    @Test("parsePlaylistVideoRenderer extracts setVideoId from the playlist listing response")
    func parsePlaylistVideoRendererExtractsSetVideoId() async throws {
        let json: [String: Any] = [
            "items": [
                [
                    "playlistVideoRenderer": [
                        "videoId": "VID123",
                        "setVideoId": "PL_SET_VIDEO_TOKEN_2",
                        "title": ["simpleText": "A video"],
                        "shortBylineText": ["runs": [["text": "Channel"]]],
                        "thumbnail": [
                            "thumbnails": [["url": "https://example.com/thumb.jpg", "width": 120, "height": 90]]
                        ],
                    ]
                ]
            ]
        ]
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(json, title: nil)
        #expect(group.videos.count == 1)
        #expect(
            group.videos.first?.setVideoId == "PL_SET_VIDEO_TOKEN_2",
            "playlistVideoRenderer.setVideoId must be threaded onto the parsed Video so removal can use it later"
        )
    }

    @Test("addToWatchLater returns the new entry's setVideoId from the response (#157)")
    func addToWatchLaterReturnsSetVideoId() async throws {
        let response = #"{"status":"STATUS_SUCCEEDED","playlistEditResults":[{"playlistEditVideoAddedResultData":{"videoId":"vid1","setVideoId":"NEW_ENTRY_TOKEN"}}]}"#
        StubURLProtocol.responses = ["browse/edit_playlist": (200, Data(response.utf8))]
        StubURLProtocol.capturedBodies = [:]
        let token = try await makeAPI().addToWatchLater(videoId: "vid1")
        #expect(token == "NEW_ENTRY_TOKEN")
    }

    @Test("addToWatchLater returns nil when the response has no token")
    func addToWatchLaterWithoutToken() async throws {
        StubURLProtocol.responses = ["browse/edit_playlist": (200, Data("{}".utf8))]
        StubURLProtocol.capturedBodies = [:]
        let token = try await makeAPI().addToWatchLater(videoId: "vid1")
        #expect(token == nil)
    }
}
