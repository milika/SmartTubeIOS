import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsTabView
//
// Root of the Shorts tab: a seedless YouTube Shorts feed (personalised when signed
// in) in `ShortsPlayerView`'s tab mode. The player is created on first appearance,
// not when the TabView builds its tabs — `ShortsEmbedPlayerViewModel` builds a
// WKWebView in its init — and then kept, so switching tabs and back resumes the
// same Short instead of starting a new feed.

struct ShortsTabView: View {
    let api: InnerTubeAPI
    @State private var hasAppeared = false
    #if os(iOS)
    @Environment(PlayerStateStore.self) private var playerState
    @Environment(TOSPlayerStateStore.self) private var tosState
    #endif

    /// Another player went full screen over the Shorts tab — pause the Short.
    private var isSuspended: Bool {
        #if os(iOS)
        playerState.presentation == .fullScreen || tosState.presentation == .fullScreen
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasAppeared {
                ShortsPlayerView(source: .algorithm(seed: nil), api: api, mode: .tab, isSuspended: isSuspended)
            }
        }
        .onAppear { hasAppeared = true }
        .accessibilityIdentifier(AccessibilityID.Shorts.tab)
    }
}
