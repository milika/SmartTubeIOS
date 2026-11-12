import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Mirrors the WEB `reel/reel_item_watch` response (metadata params, captured
/// 2026-11-11), trimmed to the structured-description panel the parser reads.
@Suite("Shorts description parser")
struct ShortsDescriptionParserTests {

    private func factoid(_ value: String, _ label: String) -> [String: Any] {
        [
            "factoidRenderer": [
                "value": ["simpleText": value], "label": ["simpleText": label], "accessibilityText": "a11y",
            ]
        ]
    }

    private func response(items: [[String: Any]]) -> [String: Any] {
        [
            "engagementPanels": [
                ["engagementPanelSectionListRenderer": ["content": ["sectionListRenderer": [:]]]],
                [
                    "engagementPanelSectionListRenderer": [
                        "content": ["structuredDescriptionContentRenderer": ["items": items]]
                    ]
                ],
            ]
        ]
    }

    private var header: [String: Any] {
        [
            "videoDescriptionHeaderRenderer": [
                "title": ["runs": [["text": "The Last Ranking "], ["text": "#shorts"]]],
                "channel": ["simpleText": "Silenthaze"],
                "channelNavigationEndpoint": ["browseEndpoint": ["browseId": "UCabc"]],
                "channelThumbnail": ["thumbnails": [["url": "//yt3.ggpht.com/avatar=s88"]]],
                "factoid": [
                    factoid("88K", "Likes"),
                    [
                        "viewCountFactoidRenderer": [
                            "factoid": factoid("3,383,710", "Views"),
                            "viewCountType": "VIEW_COUNT_FACTOID_TYPE_TOTAL_VIEWS",
                        ]
                    ],
                    factoid("Nov 5", "2026"),
                ],
            ]
        ]
    }

    @Test("Parses title, channel, the three tiles and the description text")
    func parsesHeaderAndBody() throws {
        let body: [String: Any] = [
            "expandableVideoDescriptionBodyRenderer": ["descriptionBodyText": ["runs": [["text": "Credit: @someone"]]]]
        ]
        let parsed = try #require(ShortsDescriptionParser.parse(response(items: [header, body]), videoId: "v1"))

        #expect(parsed.videoId == "v1")
        #expect(parsed.title == "The Last Ranking #shorts")
        #expect(parsed.channelTitle == "Silenthaze")
        #expect(parsed.channelId == "UCabc")
        #expect(parsed.channelAvatarURL?.absoluteString == "https://yt3.ggpht.com/avatar=s88")
        #expect(parsed.factoids.map(\.value) == ["88K", "3,383,710", "Nov 5"])
        #expect(parsed.factoids.map(\.label) == ["Likes", "Views", "2026"])
        #expect(parsed.descriptionText == "Credit: @someone")
    }

    @Test("A Short without description text still parses")
    func noBody() throws {
        let parsed = try #require(ShortsDescriptionParser.parse(response(items: [header]), videoId: "v1"))
        #expect(parsed.descriptionText.isEmpty)
    }

    @Test("Empty runs in one description shape don't hide the text in the other")
    func emptyRunsFallBackToAttributedText() throws {
        let body: [String: Any] = [
            "expandableVideoDescriptionBodyRenderer": [
                "descriptionBodyText": ["runs": [[String: Any]]()],
                "attributedDescriptionBodyText": ["content": "Credit: @someone"],
            ]
        ]
        let parsed = try #require(ShortsDescriptionParser.parse(response(items: [header, body]), videoId: "v1"))
        #expect(parsed.descriptionText == "Credit: @someone")
    }

    @Test("No structured description panel → nil")
    func missingPanel() {
        #expect(ShortsDescriptionParser.parse(["engagementPanels": []], videoId: "v1") == nil)
        #expect(ShortsDescriptionParser.parse(response(items: []), videoId: "v1") == nil)
    }
}
