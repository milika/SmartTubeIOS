import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// Shorts thumbnails rendered as YouTube's grey "•••" placeholder: i.ytimg.com
// answers a missing thumbnail with 404 and a valid JPEG body, which AsyncImage
// showed as success, so the fallback chain never ran.

private final class ThumbnailStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: Self.statusCode, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/jpeg"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Thumbnail loading", .serialized)
struct ThumbnailLoadingTests {
    private let url = URL(string: "https://i.ytimg.com/vi/abcdefghijk/oardefault.jpg")!
    /// Stand-in for the placeholder JPEG body; any bytes do, the status decides.
    private let placeholderBody = Data([0xFF, 0xD8, 0xFF, 0xE0])

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThumbnailStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("a 404 with an image body is a failure, not the placeholder image")
    func notFoundWithImageBodyThrows() async {
        ThumbnailStubURLProtocol.statusCode = 404
        ThumbnailStubURLProtocol.body = placeholderBody
        await #expect(throws: ThumbnailLoader.HTTPStatusError(statusCode: 404)) {
            try await ThumbnailLoader.imageData(from: url, session: makeSession())
        }
    }

    @Test("a 200 returns the body")
    func okReturnsBody() async throws {
        ThumbnailStubURLProtocol.statusCode = 200
        ThumbnailStubURLProtocol.body = placeholderBody
        let data = try await ThumbnailLoader.imageData(from: url, session: makeSession())
        #expect(data == placeholderBody)
    }

    @Test("Shorts fall back from the cover to the generated portrait frame, then hqdefault")
    func portraitFallbackOrder() {
        let video = Video(id: "abcdefghijk", title: "", channelTitle: "", isShort: true, hasPortraitThumbnail: true)
        let names = video.portraitThumbnailFallbackURLs(excluding: video.portraitThumbnailURL)
            .map(\.lastPathComponent)
        #expect(names == ["oar2.jpg", "hqdefault.jpg"])
    }

    @Test("an API-provided Short thumbnail keeps the whole portrait chain as fallbacks")
    func portraitFallbacksAfterAPIThumbnail() {
        let api = URL(string: "https://i.ytimg.com/vi/abcdefghijk/hq2.jpg?sqp=x")!
        let video = Video(id: "abcdefghijk", title: "", channelTitle: "", thumbnailURL: api, isShort: true)
        let names = video.portraitThumbnailFallbackURLs(excluding: api).map(\.lastPathComponent)
        #expect(names == ["oardefault.jpg", "oar2.jpg", "hqdefault.jpg"])
    }
}
