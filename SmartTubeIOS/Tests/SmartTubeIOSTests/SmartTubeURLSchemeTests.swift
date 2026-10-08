import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - SmartTubeURLSchemeTests (#84)

@Suite("SmartTubeURLScheme.videoID(from:)")
struct SmartTubeURLSchemeTests {

    @Test("smarttube://video/VIDEO_ID extracts the video ID")
    func videoPathForm() throws {
        let url = try #require(URL(string: "smarttube://video/dQw4w9WgXcQ"))
        #expect(SmartTubeURLScheme.videoID(from: url) == "dQw4w9WgXcQ")
    }

    @Test("smarttube://watch?v=VIDEO_ID extracts the video ID")
    func watchQueryForm() throws {
        let url = try #require(URL(string: "smarttube://watch?v=dQw4w9WgXcQ"))
        #expect(SmartTubeURLScheme.videoID(from: url) == "dQw4w9WgXcQ")
    }

    @Test("smarttube://watch?v=VIDEO_ID with extra query params still extracts the video ID")
    func watchQueryFormWithExtraParams() throws {
        let url = try #require(URL(string: "smarttube://watch?list=PL123&v=dQw4w9WgXcQ&t=30"))
        #expect(SmartTubeURLScheme.videoID(from: url) == "dQw4w9WgXcQ")
    }

    @Test("a non-smarttube scheme returns nil")
    func wrongSchemeReturnsNil() throws {
        let url = try #require(URL(string: "https://video/dQw4w9WgXcQ"))
        #expect(SmartTubeURLScheme.videoID(from: url) == nil)
    }

    @Test("an unrecognized host returns nil")
    func unrecognizedHostReturnsNil() throws {
        let url = try #require(URL(string: "smarttube://channel/UC123"))
        #expect(SmartTubeURLScheme.videoID(from: url) == nil)
    }

    @Test("smarttube://watch with no v= query param returns nil")
    func watchWithoutVideoIDReturnsNil() throws {
        let url = try #require(URL(string: "smarttube://watch?list=PL123"))
        #expect(SmartTubeURLScheme.videoID(from: url) == nil)
    }

    @Test("smarttube://video/ with an empty path returns nil")
    func emptyVideoPathReturnsNil() throws {
        let url = try #require(URL(string: "smarttube://video/"))
        #expect(SmartTubeURLScheme.videoID(from: url) == nil)
    }
}

// MARK: - SmartTubeRouteTests (App Intents, Spotlight)

@Suite("SmartTubeRoute")
struct SmartTubeRouteTests {

    @Test(
        "every route survives a round trip through its URL",
        arguments: [
            SmartTubeRoute.video(id: "dQw4w9WgXcQ"),
            .search(query: "lofi hip hop & chill"),
            .section(.watchLater),
            .section(.subscriptions),
            .playWatchLater,
            .continueWatching,
            .channel(id: "UC_x5XG1OV2P6uZZ5FSM9Ttw"),
        ])
    func roundTrip(_ route: SmartTubeRoute) {
        #expect(SmartTubeRoute(url: route.url) == route)
    }

    @Test("existing video links still parse as video routes")
    func legacyVideoLinks() throws {
        #expect(SmartTubeRoute(url: try #require(URL(string: "smarttube://watch?v=abc123"))) == .video(id: "abc123"))
        #expect(SmartTubeRoute(url: try #require(URL(string: "smarttube://video/abc123"))) == .video(id: "abc123"))
    }

    @Test(
        "malformed or unknown links are rejected",
        arguments: [
            "smarttube://search", "smarttube://search?q=%20%20", "smarttube://section/nope",
            "smarttube://play/somethingelse", "smarttube://channel", "smarttube://unknown/x",
            "https://www.youtube.com/watch?v=abc123",
        ])
    func rejectsBadLinks(_ string: String) throws {
        #expect(SmartTubeRoute(url: try #require(URL(string: string))) == nil)
    }
}
