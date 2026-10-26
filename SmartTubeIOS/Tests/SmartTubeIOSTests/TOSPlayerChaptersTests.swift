#if !os(tvOS)
import Foundation
import Testing

@testable import SmartTubeIOSCore
@testable import SmartTubeIOS

// MARK: - TOSPlayerChaptersTests (#10, closes #68/#105)
//
// fetchRelatedVideos() already does the one fetchNextInfo round trip TOSPlayerViewModel
// needs for swipe navigation; NextInfo also carries chapters (parsed by
// InnerTubeAPI+Social.swift's parseChapters from the same /next response), so
// fetchRelatedVideos() was extended to also stash them on vm.chapters — no extra
// network cost. This proves that wiring, not the parser itself (see
// InnerTubeAPI+VideoRenderers.swift's own chapter-parsing tests for that).

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
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

@Suite("TOS player chapters wiring (#10)", .serialized)
@MainActor
struct TOSPlayerChaptersTests {

    private func nextResponseWithChapters() -> Data {
        let json: [String: Any] = [
            "engagementPanels": [
                [
                    "engagementPanelSectionListRenderer": [
                        "content": [
                            "macroMarkersListRenderer": [
                                "contents": [
                                    [
                                        "macroMarkersListItemRenderer": [
                                            "title": ["simpleText": "Intro"],
                                            "onTap": ["watchEndpoint": ["startTimeSeconds": 0]],
                                        ]
                                    ],
                                    [
                                        "macroMarkersListItemRenderer": [
                                            "title": ["simpleText": "The main part"],
                                            "onTap": ["watchEndpoint": ["startTimeSeconds": 90]],
                                        ]
                                    ],
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test("fetchRelatedVideos populates vm.chapters from the same /next response")
    func fetchRelatedVideosPopulatesChapters() async throws {
        StubURLProtocol.responses = ["next": (200, nextResponseWithChapters())]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = InnerTubeAPI(authToken: nil, session: session)

        let vm = TOSPlayerViewModel(videoId: "test_chapters_video", api: api)
        await vm.fetchRelatedVideos()

        #expect(vm.chapters.count == 2)
        #expect(vm.chapters.first?.title == "Intro")
        #expect(vm.chapters.first?.startTime == 0)
        #expect(vm.chapters.last?.title == "The main part")
        #expect(vm.chapters.last?.startTime == 90)
    }

    @Test("vm.chapters is empty by default (before fetchRelatedVideos completes)")
    func chaptersEmptyByDefault() {
        let vm = TOSPlayerViewModel(videoId: "test_chapters_default", api: InnerTubeAPI())
        #expect(vm.chapters.isEmpty)
    }

    @Test("hasNextChapter / hasPreviousChapter mirror the playhead")
    func chapterFlags() {
        let vm = TOSPlayerViewModel(videoId: "test_chapter_flags", api: InnerTubeAPI())
        vm.chapters = [
            Chapter(title: "Intro", startTime: 0),
            Chapter(title: "Main", startTime: 90),
        ]

        vm.currentTime = 0
        #expect(vm.hasNextChapter)
        #expect(vm.hasPreviousChapter == false)  // first chapter, at its start

        vm.currentTime = 10
        #expect(vm.hasPreviousChapter)  // >3s into the first chapter → restart it

        vm.currentTime = 91
        #expect(vm.hasNextChapter == false)  // last chapter
        #expect(vm.hasPreviousChapter)  // 1s into "Main" → jump back to "Intro"

        vm.currentTime = 200
        #expect(vm.hasNextChapter == false)
        #expect(vm.hasPreviousChapter)
    }

    @Test("both chapter flags are false without chapters")
    func chapterFlagsWithoutChapters() {
        let vm = TOSPlayerViewModel(videoId: "test_no_chapters", api: InnerTubeAPI())
        vm.currentTime = 42
        #expect(vm.hasNextChapter == false)
        #expect(vm.hasPreviousChapter == false)
    }

    @Test("video prev/next buttons are gated on playlist membership")
    func playlistButtonGating() {
        let plain = TOSPlayerViewModel(videoId: "test_plain", api: InnerTubeAPI())
        plain.playlistVideoCount = 5
        #expect(plain.isInPlaylist == false)
        #expect(plain.canPlayPreviousVideo == false)
        #expect(plain.canPlayNextVideo == false)

        let inQueue = TOSPlayerViewModel(
            videoId: "test_queue",
            playlistId: CurrentQueueStore.playlistID,
            playlistIndex: 0,
            api: InnerTubeAPI()
        )
        inQueue.playlistVideoCount = 1
        #expect(inQueue.isInPlaylist)
        #expect(inQueue.canPlayPreviousVideo == false)  // nothing to navigate

        inQueue.playlistVideoCount = 3
        #expect(inQueue.canPlayPreviousVideo)
        #expect(inQueue.canPlayNextVideo)
    }
}
#endif
