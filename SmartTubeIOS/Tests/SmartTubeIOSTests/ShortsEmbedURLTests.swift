import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("ShortsEmbedURL")
struct ShortsEmbedURLTests {

    @Test("embedURL targets youtube.com/embed/<videoId>")
    func embedURLHasCorrectPathAndHost() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-")
        #expect(url.host == "www.youtube.com")
        #expect(url.path == "/embed/abc123XYZ_-")
    }

    @Test("embedURL includes the expected query items")
    func embedURLHasExpectedQueryItems() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-", startTime: 5)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(dict["autoplay"] == "1")
        #expect(dict["mute"] == "1")
        #expect(dict["controls"] == "0")
        #expect(dict["playsinline"] == "1")
        #expect(dict["rel"] == "0")
        #expect(dict["iv_load_policy"] == "3")
        #expect(dict["start"] == "5")
        #expect(dict["origin"] == "https://www.example.com")
    }

    @Test("embedURL truncates a fractional startTime to whole seconds")
    func embedURLTruncatesStartTime() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-", startTime: 12.9)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "start" }?.value == "12")
    }

    @Test("embedURL defaults startTime to 0")
    func embedURLDefaultsStartTimeToZero() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "start" }?.value == "0")
    }

    @Test("htmlWrapper embeds the iframe with id=\"yt\" and the given URL")
    func htmlWrapperContainsIframeWithEmbedURL() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-")
        let html = ShortsEmbedURL.htmlWrapper(embedURL: url)
        #expect(html.contains("id=\"yt\""))
        #expect(html.contains(url.absoluteString))
    }

    @Test("videoId(fromEmbedURL:) round-trips embedURL's videoId")
    func videoIdRoundTripsEmbedURL() {
        let url = ShortsEmbedURL.embedURL(videoId: "abc123XYZ_-")
        #expect(ShortsEmbedURL.videoId(fromEmbedURL: url) == "abc123XYZ_-")
    }

    @Test("videoId(fromEmbedURL:) returns nil for a non-embed URL")
    func videoIdReturnsNilForUnrelatedURL() {
        let url = URL(string: "https://www.youtube.com/watch?v=abc123")!
        #expect(ShortsEmbedURL.videoId(fromEmbedURL: url) == nil)
    }
}
