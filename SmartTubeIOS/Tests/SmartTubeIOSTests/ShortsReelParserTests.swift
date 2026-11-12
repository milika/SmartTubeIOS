import Foundation
import Testing

@testable import SmartTubeIOSCore

/// The JSON below mirrors the TVHTML5 `reel/*` responses captured on 2026-11-11
/// (see docs/superpowers/plans/2026-11-11-shorts-algorithm-feed-and-ui.md), trimmed
/// to the fields the parser reads.
@Suite("Shorts reel parser")
struct ShortsReelParserTests {

    private func entry(_ id: String) -> [String: Any] {
        [
            "command": [
                "reelWatchEndpoint": [
                    "videoId": id,
                    "thumbnail": [
                        "thumbnails": [
                            ["url": "https://i.ytimg.com/vi/\(id)/frame0.jpg", "width": 1080, "height": 1920]
                        ]
                    ],
                ]
            ]
        ]
    }

    private func responseContext(loggedIn: String) -> [String: Any] {
        ["serviceTrackingParams": [["service": "GFEEDBACK", "params": [["key": "logged_in", "value": loggedIn]]]]]
    }

    @Test("Sequence → Shorts in order, deduplicated, with portrait thumbnails and the TV continuation")
    func parsesSequence() {
        let json: [String: Any] = [
            "entries": [entry("aaa"), entry("bbb"), entry("aaa"), ["command": [:]]],
            "continuation": "NEXT",
        ]
        let parsed = ShortsReelParser.parseSequence(json)
        #expect(parsed.videos.map(\.id) == ["aaa", "bbb"])
        #expect(parsed.videos.allSatisfy { $0.isShort && $0.hasPortraitThumbnail })
        #expect(parsed.videos.first?.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/aaa/frame0.jpg")
        #expect(parsed.continuation == "NEXT")
    }

    /// A sequence entry as YouTube marks an ad, from a 2026-11-12 capture.
    private func adEntry(_ id: String, isAd: Bool = true, videoType: String = "REEL_VIDEO_TYPE_AD") -> [String: Any] {
        var endpoint: [String: Any] = ["videoId": id, "videoType": videoType]
        if isAd { endpoint["adClientParams"] = ["isAd": true] }
        return ["command": ["reelWatchEndpoint": endpoint]]
    }

    @Test("Sequence leaves out Shorts ads, whichever of the two markers they carry")
    func skipsAds() {
        let json: [String: Any] = [
            "entries": [
                entry("aaa"), adEntry("ad1"), adEntry("ad2", isAd: false),
                adEntry("ad3", videoType: "REEL_VIDEO_TYPE_VIDEO"), entry("bbb"),
            ],
            "continuation": "NEXT",
        ]
        #expect(ShortsReelParser.parseSequence(json).videos.map(\.id) == ["aaa", "bbb"])
    }

    @Test("A seedless start that is an ad gives no first Short but keeps the sequence")
    func seedlessAd() throws {
        let json: [String: Any] = [
            "replacementEndpoint": try #require(adEntry("ad")["command"]),
            "sequenceContinuation": "SEQ",
        ]
        let parsed = ShortsReelParser.parseSeedless(json)
        #expect(parsed.first == nil)
        #expect(parsed.sequenceParams == "SEQ")
    }

    @Test("Sequence also reads the WEB continuationEndpoint shape")
    func parsesWebContinuation() {
        let json: [String: Any] = [
            "entries": [entry("aaa")],
            "continuationEndpoint": ["continuationCommand": ["token": "WEBNEXT"]],
        ]
        #expect(ShortsReelParser.parseSequence(json).continuation == "WEBNEXT")
    }

    @Test("Seedless item watch → first Short and the sequence params")
    func parsesSeedless() throws {
        let json: [String: Any] = [
            "replacementEndpoint": try #require(entry("first")["command"]),
            "sequenceContinuation": "SEQ",
        ]
        let parsed = ShortsReelParser.parseSeedless(json)
        #expect(parsed.first?.id == "first")
        #expect(parsed.sequenceParams == "SEQ")
    }

    @Test("logged_in flag is read from GFEEDBACK tracking params")
    func parsesLoggedIn() {
        #expect(ShortsReelParser.parseLoggedIn(["responseContext": responseContext(loggedIn: "1")]) == true)
        #expect(ShortsReelParser.parseLoggedIn(["responseContext": responseContext(loggedIn: "0")]) == false)
        #expect(ShortsReelParser.parseLoggedIn([:]) == nil)
    }

    @Test("Metadata → title, channel, avatar, subscribe state, like status and counts")
    func parsesMetadata() throws {
        let likeButton: [String: Any] = [
            "likeButtonViewModel": [
                "likeStatusEntity": ["likeStatus": "LIKE"],
                "toggleButtonViewModel": [
                    "toggleButtonViewModel": [
                        "defaultButtonViewModel": ["buttonViewModel": ["title": "1.1K"]],
                        "toggledButtonViewModel": ["buttonViewModel": ["title": "1.2K"]],
                    ]
                ],
            ]
        ]
        let commentButton: [String: Any] = [
            "buttonViewModel": ["iconName": "COMMENT", "title": "239", "accessibilityText": "View 239 comments"]
        ]
        let json: [String: Any] = [
            "overlay": [
                "reelPlayerOverlayRenderer": [
                    "reelPlayerHeaderSupportedRenderers": [
                        "reelPlayerHeaderRenderer": [
                            "reelTitleText": ["runs": [["text": "Physics "], ["text": "#sports"]]],
                            "timestampText": ["simpleText": "5 days ago"],
                            "channelNavigationEndpoint": ["browseEndpoint": ["browseId": "UC123"]],
                            "channelTitleText": ["runs": [["text": "@Chan"]]],
                            "channelThumbnail": [
                                "thumbnails": [
                                    ["url": "https://yt3.ggpht.com/a=s48", "width": 48],
                                    ["url": "https://yt3.ggpht.com/a=s176", "width": 176],
                                ]
                            ],
                        ]
                    ],
                    "subscribeButtonRenderer": [
                        "subscribeButtonRenderer": ["subscribed": true, "channelId": "UC123"]
                    ],
                    "buttonBar": [
                        "reelActionBarViewModel": [
                            "buttonViewModels": [
                                ["reelActionBarButtonViewModel": ["buttonViewModel": likeButton]],
                                ["reelActionBarButtonViewModel": ["buttonViewModel": commentButton]],
                            ]
                        ]
                    ],
                ]
            ]
        ]
        let metadata = try #require(ShortsReelParser.parseMetadata(json, videoId: "vid"))
        #expect(metadata.title == "Physics #sports")
        #expect(metadata.channelTitle == "@Chan")
        #expect(metadata.channelId == "UC123")
        #expect(metadata.channelAvatarURL?.absoluteString == "https://yt3.ggpht.com/a=s176")
        #expect(metadata.publishedTimeText == "5 days ago")
        #expect(metadata.isSubscribed)
        #expect(metadata.likeStatus == .like)
        #expect(metadata.likeCountText == "1.2K")  // toggled state's title while liked
        #expect(metadata.commentCountText == "239")
    }

    @Test("A plain 'Like' label is not a count")
    func hiddenCounts() {
        #expect(ShortsReelParser.countText("Like") == nil)
        #expect(ShortsReelParser.countText("Comment") == nil)
        #expect(ShortsReelParser.countText("12") == "12")
    }

    @Test("No overlay → nil metadata")
    func missingOverlay() {
        #expect(ShortsReelParser.parseMetadata([:], videoId: "vid") == nil)
    }

    @Test("Seed sequenceParams encode the video id as protobuf field 1")
    func seedParams() throws {
        let encoded = ShortsSequenceParams.seed(videoId: "UV6pckLzL_c")
        #expect(encoded == "CgtVVjZwY2tMekxfYyoCGAJQGWgA")  // value verified against YouTube in the spike
        let data = try #require(Data(base64Encoded: encoded))
        #expect(data.prefix(2) == Data([0x0A, 0x0B]))
        #expect(String(data: data.dropFirst(2).prefix(11), encoding: .utf8) == "UV6pckLzL_c")
    }
}
