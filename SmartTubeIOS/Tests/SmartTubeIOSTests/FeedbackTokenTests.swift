import Foundation
import Testing

@testable import SmartTubeIOSCore

/// `InnerTubeAPI.feedbackToken(iconType:videoId:in:)` must only return a token from
/// the target video's own menu, never one from a recommendation in the same `/next`.
@Suite("Feedback token targeting")
struct FeedbackTokenTests {

    private func menuItem(_ iconType: String, token: String) -> [String: Any] {
        [
            "menuServiceItemRenderer": [
                "icon": ["iconType": iconType],
                "serviceEndpoint": ["feedbackEndpoint": ["feedbackToken": token]],
            ]
        ]
    }

    private func compactVideo(_ id: String, items: [[String: Any]]) -> [String: Any] {
        ["compactVideoRenderer": ["videoId": id, "menu": ["menuRenderer": ["items": items]]]]
    }

    private func next(_ results: [[String: Any]], primaryMenu: [[String: Any]] = []) -> [String: Any] {
        [
            "contents": [
                "twoColumnWatchNextResults": [
                    "results": ["results": ["contents": [["menuRenderer": ["items": primaryMenu]]]]],
                    "secondaryResults": ["secondaryResults": ["results": results]],
                ]
            ]
        ]
    }

    @Test("Another video's token is never sent for the current one")
    func ignoresOtherVideosTokens() {
        let json = next([compactVideo("other", items: [menuItem("BLOCK_CHANNEL", token: "OTHER")])])
        #expect(InnerTubeAPI.feedbackToken(iconType: "BLOCK_CHANNEL", videoId: "mine", in: json) == nil)
    }

    @Test("The target video's own token is found among the others")
    func findsOwnToken() {
        let json = next([
            compactVideo("other", items: [menuItem("NOT_INTERESTED", token: "OTHER")]),
            compactVideo(
                "mine", items: [menuItem("BLOCK_CHANNEL", token: "B"), menuItem("NOT_INTERESTED", token: "N")]),
        ])
        #expect(InnerTubeAPI.feedbackToken(iconType: "NOT_INTERESTED", videoId: "mine", in: json) == "N")
    }

    @Test("A token whose video can't be told is skipped")
    func skipsUnownedToken() {
        let json = next([], primaryMenu: [menuItem("NOT_INTERESTED", token: "UNKNOWN")])
        #expect(InnerTubeAPI.feedbackToken(iconType: "NOT_INTERESTED", videoId: "mine", in: json) == nil)
    }
}
