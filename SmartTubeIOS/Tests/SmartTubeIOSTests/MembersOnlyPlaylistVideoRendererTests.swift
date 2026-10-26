import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - MembersOnlyPlaylistVideoRendererTests (#63)
//
// Extends task #227's members-only filtering (originally parseTileRenderer only) to
// parsePlaylistVideoRenderer, which serves the same Home/Subscriptions/History feeds
// for videos that arrive in the WEB-shaped renderer instead of the TV tile shape. Two
// of the three original signals (thumbnailOverlayMembershipBadgeRenderer,
// metadataBadgeRenderer) are shared via isMembersOnlyVideo(overlays:badges:) — see
// MembersOnlyHomeFeedFilterTests for the parseTileRenderer-side coverage of those same
// signals, and InnerTubeAPI+VideoRenderers.swift's doc comment on isMembersOnlyVideo.

@Suite("Members-only filter in parsePlaylistVideoRenderer (#63)")
struct MembersOnlyPlaylistVideoRendererTests {

    private let api = InnerTubeAPI()

    private func makeRendererJSON(
        videoId: String, extraOverlays: [[String: Any]] = [], badges: [[String: Any]] = []
    ) -> [String: Any] {
        var overlays: [[String: Any]] = [
            ["thumbnailOverlayTimeStatusRenderer": ["text": ["simpleText": "8:34"], "style": "DEFAULT"]]
        ]
        overlays.append(contentsOf: extraOverlays)
        return [
            "playlistVideoRenderer": [
                "videoId": videoId,
                "title": ["simpleText": "Test Video"],
                "shortBylineText": ["runs": [["text": "Test Channel"]]],
                "thumbnail": [
                    "thumbnails": [["url": "https://example.com/thumb.jpg", "width": 120, "height": 90]]
                ],
                "thumbnailOverlays": overlays,
                "badges": badges,
            ]
        ]
    }

    @Test("Signal 1: thumbnailOverlayMembershipBadgeRenderer flags the video as members-only")
    func membershipOverlayFlags() async throws {
        let json: [String: Any] = [
            "items": [
                makeRendererJSON(
                    videoId: "MEMBERS_1",
                    extraOverlays: [["thumbnailOverlayMembershipBadgeRenderer": [:]]]
                )
            ]
        ]
        let group = try await api.parseVideoGroupForTesting(json, title: nil)
        #expect(group.videos.count == 1)
        #expect(group.videos.first?.id == "MEMBERS_1")
        #expect(group.videos.first?.isMembersOnly == true)
    }

    @Test("Signal 2: metadataBadgeRenderer with MEMBERS_ONLY icon type flags the video as members-only")
    func memberBadgeFlags() async throws {
        let json: [String: Any] = [
            "items": [
                makeRendererJSON(
                    videoId: "MEMBERS_2",
                    badges: [
                        [
                            "metadataBadgeRenderer": [
                                "icon": ["iconType": "MEMBERS_ONLY"], "label": "Members only",
                            ]
                        ]
                    ]
                )
            ]
        ]
        let group = try await api.parseVideoGroupForTesting(json, title: nil)
        #expect(group.videos.count == 1)
        #expect(group.videos.first?.id == "MEMBERS_2")
        #expect(group.videos.first?.isMembersOnly == true)
    }

    @Test("a regular video (no membership signal) is included in the feed")
    func regularVideoIncluded() async throws {
        let json: [String: Any] = ["items": [makeRendererJSON(videoId: "REGULAR_1")]]
        let group = try await api.parseVideoGroupForTesting(json, title: nil)
        #expect(group.videos.count == 1)
        #expect(group.videos.first?.id == "REGULAR_1")
    }
}
