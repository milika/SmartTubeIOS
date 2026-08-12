#if os(iOS)
import Foundation
import SmartTubeIOSCore

// MARK: - PlayerRouter
//
// Single "open this video" decision point for iOS.
//
// Every place in the app that lets the user tap a video (Home, Search, Browse,
// Channel, Playlist, Library, RSS, and the deep-link / Share-Extension handlers
// in RootView) calls `open(video:api:)` instead of reaching into
// `PlayerStateStore` or `TOSPlayerStateStore` directly. That keeps the
// TOS-vs-AVPlayer routing decision — and the mini-player conflict rule — in one
// place instead of duplicated across every view.
//
// Routing rules:
//   - If the effective iOS player selection is the YouTube embed and this video
//     hasn't previously hit a fatal embed error, present the WKWebView-based player.
//   - Otherwise present the AVPlayer-based pipeline.
// In both cases, any active mini-player for the *other* pipeline is stopped
// first — AVPlayer and TOS playback are mutually exclusive.
@MainActor
@Observable
public final class PlayerRouter {
    enum Route: Equatable {
        case youtubeEmbed
        case native
    }

    private let playerState: PlayerStateStore
    private let tosState: TOSPlayerStateStore
    private let settingsStore: SettingsStore

    public init(playerState: PlayerStateStore, tosState: TOSPlayerStateStore, settingsStore: SettingsStore) {
        self.playerState = playerState
        self.tosState = tosState
        self.settingsStore = settingsStore
    }

    func route(for video: Video) -> Route {
        if settingsStore.effectiveIOSPlayer == .youtubeEmbed,
           tosState.fallbackVideoId != video.id {
            return .youtubeEmbed
        }
        return .native
    }

    /// Open `video` in whichever player pipeline is currently preferred.
    public func open(video: Video, api: InnerTubeAPI) {
        if route(for: video) == .youtubeEmbed {
            if playerState.presentation != .hidden { playerState.stop() }
            tosState.play(video: video, api: api)
            return
        }
        if tosState.presentation != .hidden { tosState.stop() }
        // PlayerStateStore.play() starts loading synchronously, before PlayerView.onAppear
        // can propagate preferences. Seed them here so the very first stream attempt uses
        // the selected quality, playback speed, and background-playback configuration.
        playerState.vm.updateSettings(settingsStore.settings)
        playerState.play(video: video)
    }
}
#endif // os(iOS)
