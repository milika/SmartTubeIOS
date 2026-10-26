import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - Lockup badge parsing (LIVE / Members)
//
// `lockupViewModel` is the WEB home/search shape (and TVHTML5 search). It has no
// duration, so the card's LIVE and "Members" tags must come from the thumbnail
// badge overlays rather than time/duration heuristics.

private func makeLockupResponse(_ lockup: [String: Any]) -> [String: Any] {
    [
        "contents": [
            "sectionListRenderer": [
                "contents": [
                    [
                        "itemSectionRenderer": [
                            "contents": [["lockupViewModel": lockup]]
                        ]
                    ]
                ]
            ]
        ]
    ]
}

private func makeLockup(
    videoId: String,
    badges: [[String: Any]],
    metadataRows: [[String: Any]] = []
) -> [String: Any] {
    [
        "contentImage": [
            "thumbnailViewModel": [
                "image": [
                    "sources": [
                        ["url": "https://example.com/thumb.jpg", "width": 640, "height": 360]
                    ]
                ],
                "overlays": [
                    ["thumbnailBottomOverlayViewModel": ["badges": badges]]
                ],
            ]
        ],
        "metadata": [
            "lockupMetadataViewModel": [
                "title": ["content": "Test Video"],
                "metadata": [
                    "contentMetadataViewModel": [
                        "metadataRows": [
                            [
                                "metadataParts": [
                                    ["text": ["content": "Test Channel"]]
                                ]
                            ]
                        ] + metadataRows
                    ]
                ],
            ]
        ],
        "rendererContext": [
            "commandContext": [
                "onTap": [
                    "innertubeCommand": [
                        "watchEndpoint": ["videoId": videoId]
                    ]
                ]
            ]
        ],
    ]
}

@Suite("lockupViewModel badge parsing (LIVE / Members)")
struct LockupBadgeParsingTests {

    private let api = InnerTubeAPI()

    @Test("LIVE badge → isLive = true")
    func liveBadge() async throws {
        let lockup = makeLockup(
            videoId: "liveVideo",
            badges: [
                [
                    "thumbnailBadgeViewModel": [
                        "text": "LIVE",
                        "badgeStyle": "THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE",
                    ]
                ]
            ]
        )
        let group = try await api.parseVideoGroupForTesting(makeLockupResponse(lockup), title: "Home")
        let video = try #require(group.videos.first)
        #expect(video.isLive == true)
        #expect(video.isShort == false, "A live broadcast must not be treated as a Short")
    }

    @Test("Members badge → isMembersOnly = true")
    func membersBadge() async throws {
        let lockup = makeLockup(
            videoId: "membersVideo",
            badges: [
                [
                    "thumbnailBadgeViewModel": [
                        "text": "Members only",
                        "badgeStyle": "THUMBNAIL_OVERLAY_BADGE_STYLE_MEMBERS_ONLY",
                    ]
                ]
            ]
        )
        let group = try await api.parseVideoGroupForTesting(makeLockupResponse(lockup), title: "Home")
        let video = try #require(group.videos.first)
        #expect(video.isMembersOnly == true)
    }

    @Test("Members-only metadata text → isMembersOnly = true")
    func membersMetadataText() async throws {
        let lockup = makeLockup(
            videoId: "membersText",
            badges: [],
            metadataRows: [
                [
                    "metadataParts": [
                        ["text": ["content": "Members only"]]
                    ]
                ]
            ]
        )
        let group = try await api.parseVideoGroupForTesting(makeLockupResponse(lockup), title: "Home")
        let video = try #require(group.videos.first)
        #expect(video.isMembersOnly == true)
    }
}
