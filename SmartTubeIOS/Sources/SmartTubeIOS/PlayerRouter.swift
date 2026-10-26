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
//   - If `settingsStore.useTOSPlayerOnIOS` is true (the persisted default, unless the
//     user selects Native Player or a UI test overrides it) and this video hasn't hit a fatal embed
//     error (TOSPlayerStateStore.fallbackVideoId), present the WKWebView-based
//     TOS-compliant player.
//   - Otherwise present the AVPlayer-based pipeline.
// In both cases, any active mini-player for the *other* pipeline is stopped
// first — AVPlayer and TOS playback are mutually exclusive.
@MainActor
@Observable
public final class PlayerRouter {
    private let playerState: PlayerStateStore
    private let tosState: TOSPlayerStateStore
    private let settingsStore: SettingsStore

    public init(playerState: PlayerStateStore, tosState: TOSPlayerStateStore, settingsStore: SettingsStore) {
        self.playerState = playerState
        self.tosState = tosState
        self.settingsStore = settingsStore
    }

    /// Open `video` in whichever player pipeline is currently preferred.
    /// `incognito` (#94) skips recording this video to watch history / resume
    /// position — currently only honored by the TOS pipeline (the iOS default);
    /// the legacy AVPlayer pipeline's history recording isn't wired to it yet.
    public func open(video: Video, api: InnerTubeAPI, incognito: Bool = false) {
        if settingsStore.useTOSPlayerOnIOS && tosState.fallbackVideoId != video.id {
            if playerState.presentation != .hidden { playerState.stop() }
            tosState.play(video: video, api: api, incognito: incognito)
            return
        }
        if tosState.presentation != .hidden { tosState.stop() }
        playerState.play(video: video)
    }
}
#endif  // os(iOS)
