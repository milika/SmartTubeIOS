import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsTabView
//
// Root of the Shorts tab: a seedless YouTube Shorts feed (personalised when signed
// in) in `ShortsPlayerView`'s tab mode. The player is created on first appearance,
// not when the TabView builds its tabs — `ShortsEmbedPlayerViewModel` builds a
// WKWebView in its init — and then kept, so switching tabs and back resumes the
// same Short instead of starting a new feed.
//
// The feed is rebuilt when the account changes (sign-in, sign-out, Brand Account
// switch), because YouTube personalises the sequence per account. A token refresh
// keeps the same account, so it does not restart the feed.

struct ShortsTabView: View {
    let api: InnerTubeAPI
    @Environment(AuthService.self) private var auth
    @State private var hasAppeared = false
    /// The account the current feed was loaded for; nil until the first load.
    @State private var loadedAccount: AccountKey?
    #if os(iOS)
    @Environment(PlayerStateStore.self) private var playerState
    @Environment(TOSPlayerStateStore.self) private var tosState
    #endif

    private struct AccountKey: Hashable {
        let hasToken: Bool
        let pageId: String?
    }

    private var currentAccount: AccountKey {
        AccountKey(hasToken: auth.accessToken != nil, pageId: auth.activePageId)
    }

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
            if hasAppeared, let loadedAccount {
                ShortsPlayerView(source: .algorithm(seed: nil), api: api, mode: .tab, isSuspended: isSuspended)
                    .id(loadedAccount)
            }
        }
        .onAppear { hasAppeared = true }
        .task(id: hasAppeared ? currentAccount : nil) {
            guard hasAppeared, currentAccount != loadedAccount else { return }
            // AppEntry hands the token to the API in its own Task; set it here too so
            // the new feed's first request cannot race ahead of it and go out signed out.
            await api.setAuthToken(auth.accessToken)
            guard !Task.isCancelled else { return }
            loadedAccount = currentAccount
        }
        .accessibilityIdentifier(AccessibilityID.Shorts.tab)
    }
}
