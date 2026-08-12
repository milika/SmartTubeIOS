#if os(iOS)
import XCTest
import SmartTubeIOSCore
@testable import SmartTubeIOS

@MainActor
final class PlayerRouterTests: XCTestCase {
    func testNativeSelectionRoutesToAVPlayer() {
        let api = InnerTubeAPI()
        let settings = SettingsStore()
        settings.settings.iOSPlayer = .native
        let nativeState = PlayerStateStore(api: api)
        let tosState = TOSPlayerStateStore()
        let router = PlayerRouter(
            playerState: nativeState,
            tosState: tosState,
            settingsStore: settings
        )

        let video = Video(id: "native-route", title: "Native", channelTitle: "Channel")
        XCTAssertEqual(router.route(for: video), .native)
    }

    func testYouTubeSelectionRoutesToEmbed() {
        let api = InnerTubeAPI()
        let settings = SettingsStore()
        settings.settings.iOSPlayer = .youtubeEmbed
        let nativeState = PlayerStateStore(api: api)
        let tosState = TOSPlayerStateStore()
        let router = PlayerRouter(
            playerState: nativeState,
            tosState: tosState,
            settingsStore: settings
        )

        let video = Video(id: "embed-route", title: "Embed", channelTitle: "Channel")
        XCTAssertEqual(router.route(for: video), .youtubeEmbed)
    }

    func testEmbedFailureRoutesThatVideoToNativePlayer() {
        let api = InnerTubeAPI()
        let settings = SettingsStore()
        settings.settings.iOSPlayer = .youtubeEmbed
        let nativeState = PlayerStateStore(api: api)
        let tosState = TOSPlayerStateStore()
        let router = PlayerRouter(
            playerState: nativeState,
            tosState: tosState,
            settingsStore: settings
        )
        let video = Video(id: "embed-fallback", title: "Fallback", channelTitle: "Channel")

        tosState.markFallback(videoId: video.id)

        XCTAssertEqual(router.route(for: video), .native)
    }
}
#endif
