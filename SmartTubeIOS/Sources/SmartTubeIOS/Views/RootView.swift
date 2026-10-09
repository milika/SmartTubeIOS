import OSLog
import SmartTubeIOSCore
import SwiftUI

private let rootLog = Logger(subsystem: "com.void.smarttube.app", category: "RootView")

// MARK: - RootView
//
// Entry point that decides whether to show the main tab UI or the
// sign-in screen.  On macOS it uses a sidebar-based navigation.

public struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    /// Shared download service — observed here so the completion alert is shown
    /// at a stable level unaffected by context menu dismiss animations on cards.
    #if ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) private var cardDownloadService
    #endif
    @State private var cardDownloadAlertItem: DownloadAlertItem?
    @State private var isLandscapeLayout = false

    public init() {}

    public var body: some View {
        @Bindable var browseVM = browseVM
        // Explicitly read cardDownloadService.state in body so SwiftUI's
        // @Observable tracking engine registers this view as a subscriber.
        // Without this, onChange(of: cardDownloadService.state) may not fire
        // when the state changes on an environment-injected @Observable object.
        #if ENABLE_DOWNLOADS
        let _ = cardDownloadService.state
        #endif
        Group {
            #if os(tvOS)
            MainTVTabView()
            #elseif os(macOS)
            MainSidebarView()
            #else
            MainTabView()
            #endif
        }
        .environment(\.isLandscapeLayout, isLandscapeLayout)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscapeLayout = $0 }
        .tint(store.settings.accentColor.color)
        .preferredColorScheme(store.settings.themeName.colorScheme)
        #if !os(tvOS) && ENABLE_DOWNLOADS
        .onChange(of: cardDownloadService.state) { _, newState in
            switch newState {
            case .done:
                cardDownloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Saved to Gallery", bundle: .module),
                    message: String(localized: "Video has been saved to your Photos library.", bundle: .module)
                )
                cardDownloadService.reset()
            case .failed(let reason):
                cardDownloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Download Failed", bundle: .module),
                    message: reason
                )
                cardDownloadService.reset()
            default:
                break
            }
        }
        .alert(
            cardDownloadAlertItem?.title ?? "",
            isPresented: Binding(
                get: { cardDownloadAlertItem != nil },
                set: { if !$0 { cardDownloadAlertItem = nil } }
            ),
            presenting: cardDownloadAlertItem
        ) { _ in
            Button("OK") { cardDownloadAlertItem = nil }
        } message: { item in
            Text(item.message)
        }
        #endif
        .sheet(isPresented: .constant(!auth.isSignedIn && requiresAuth)) {
            // Sign-in prompt is shown as a dismissible sheet so users
            // can still browse without being signed in.
            SignInView()
        }
        #if os(iOS)
        // Deep link is handled by MainTabView.onChange(of: browseVM.deepLinkedVideo)
        // which calls playerRouter.open(video:api:). No landscapePlayerCover needed here.
        #elseif !os(macOS) && !os(tvOS)
        .fullScreenCover(item: $browseVM.deepLinkedVideo) { video in
            PlayerView(video: video, api: api)
                .environment(store)
                .environment(auth)
        }
        #endif
    }

    private var requiresAuth: Bool { false }  // guest browsing is allowed
}

// MARK: - AppSection

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case library = "Library"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return AppSymbol.home
        case .search: return AppSymbol.search
        case .library: return AppSymbol.library
        case .settings: return AppSymbol.settings
        }
    }

    @MainActor @ViewBuilder
    func destination(api: InnerTubeAPI) -> some View {
        switch self {
        case .home: HomeView(api: api)
        case .search: SearchView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - MainTabView  (iOS / iPadOS)

// Propagates the bottom safe-area inset (tab bar + home indicator) from inside a
// NavigationStack tab to the enclosing MainTabView so the mini player overlay can
// be positioned exactly at the top of the tab bar without hard-coding its height.
private struct TabBarBottomInsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MainTabView: View {
    @State private var searchVM = SearchViewModel()
    @State private var selectedTab: AppSection = .home
    @State private var tabBarBottomInset: CGFloat = 0
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    #if os(iOS)
    @Environment(PlayerStateStore.self) private var playerState
    @Environment(TOSPlayerStateStore.self) private var tosState
    @Environment(PlayerRouter.self) private var playerRouter
    @Environment(BrowseViewModel.self) private var browseVM
    @State private var showSrcSwapSpike = false
    #endif

    var body: some View {
        #if os(iOS)
        // Read these in body so SwiftUI's @Observable tracker registers the dependency.
        // If only accessed inside the Binding.get closure, changes won't trigger a body re-render
        // and updateUIViewController won't be called, so the cover never dismisses.
        let fullScreenVideo: Video? = playerState.presentation == .fullScreen ? playerState.currentVideo : nil
        let _ = rootLog.notice(
            "[MainTabView] body re-render — presentation=\(String(describing: playerState.presentation)) fullScreenVideo=\(fullScreenVideo?.id ?? "nil")"
        )
        let fullScreenBinding = Binding<Video?>(
            get: { fullScreenVideo },
            set: { newValue in
                // Only transition to mini player when the cover is dismissed while
                // presentation is still .fullScreen. If stop() already moved us to
                // .hidden, the async onDismiss callback must not resurrect the mini
                // player by calling minimize() — that is the race condition that
                // caused the mini-player X button to unexpectedly restore fullscreen.
                guard newValue == nil, playerState.presentation == .fullScreen else { return }
                playerState.minimize()
            }
        )
        // TOS full-screen cover binding — mirrors the AVPlayer binding above.
        // When the user swipes down or the system dismisses the cover while TOS is
        // still in .fullScreen, this setter calls minimize() so audio continues in
        // TOSMiniPlayerView. If tosState.stop() already moved us to .hidden the
        // setter is a no-op (guard prevents spurious minimize).
        let tosFullScreenVideo: Video? = tosState.presentation == .fullScreen ? tosState.currentVideo : nil
        let tosFullScreenBinding = Binding<Video?>(
            get: { tosFullScreenVideo },
            set: { newValue in
                guard newValue == nil, tosState.presentation == .fullScreen else { return }
                tosState.minimize()
            }
        )
        #endif
        TabView(selection: $selectedTab) {
            ForEach(AppSection.allCases) { section in
                NavigationStack { section.destination(api: api) }
                    // Capture the bottom safe-area inset as seen from inside the tab
                    // (UITabBarController sets this to tab-bar height + home-indicator).
                    // The value is propagated up to tabBarBottomInset via PreferenceKey
                    // so the mini-player overlay can be positioned above the tab bar.
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: TabBarBottomInsetKey.self,
                                    value: geo.safeAreaInsets.bottom
                                )
                        }
                    }
                    .tabItem { Label(section.rawValue, systemImage: section.icon) }
                    .tag(section)
                    .accessibilityIdentifier("tab.\(section.rawValue.lowercased())")
            }
        }
        .onPreferenceChange(TabBarBottomInsetKey.self) { tabBarBottomInset = $0 }
        #if os(iOS)
        .background(TabBarLiquidGlassConfigurator(disableLiquidGlass: store.settings.disableLiquidGlass))
        #endif
        .environment(searchVM)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
            selectedTab = .search
        }
        #if os(iOS)
        // App Intents / Spotlight (see AppEntry.handleOpenURL).
        .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSearch)) { note in
            guard let query = note.userInfo?["query"] as? String else { return }
            selectedTab = .search
            searchVM.query = query
            searchVM.search()
        }
        // HomeView picks the section itself (it owns the chip selection).
        .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSection)) { _ in
            selectedTab = .home
        }
        // Reserve vertical space so scrollable tab content is not hidden under the
        // mini player. Uses a transparent placeholder rather than the real MiniPlayerView
        // to avoid duplicating the PersistentPlayerHostView UIKit layer across tabs.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Reserve vertical space for whichever mini-player is visible so
            // scrollable content is not obscured (only one can be active at a time).
            if playerState.presentation == .miniPlayer || tosState.presentation == .miniPlayer {
                Color.clear.frame(height: 62)
            }
        }
        // Render the single visible MiniPlayerView above the tab bar.
        // tabBarBottomInset = tab-bar height + home-indicator (e.g. 83 pt on Face ID
        // iPhones), read from inside the NavigationStack where UITabBarController has
        // already baked it into the safe area. The transparent passthrough spacer below
        // the mini player ensures tab-bar items remain tappable.
        .overlay(alignment: .bottom) {
            // Only one mini-player can be active at a time: AVPlayer and TOS are
            // mutually exclusive (onChange stops the other before starting the new one).
            if playerState.presentation == .miniPlayer {
                VStack(spacing: 0) {
                    MiniPlayerView()
                    Color.clear
                    .frame(height: tabBarBottomInset)
                    .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: playerState.presentation)
            } else if tosState.presentation == .miniPlayer {
                VStack(spacing: 0) {
                    TOSMiniPlayerView()
                    Color.clear
                    .frame(height: tabBarBottomInset)
                    .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: tosState.presentation)
            }
        }
        .landscapePlayerCover(item: fullScreenBinding, dismissStore: playerState) { video in
            PlayerView(video: video, api: api)
        }
        // TOS player full-screen cover — presented when tosState.presentation == .fullScreen.
        // TOSPlayerView reads tosState from the environment (injected via AppEntry) so the
        // WKWebView that was created by TOSPlayerStateStore.play(video:api:) is reused here.
        //
        // onFallback (2026-07-12): AVPlayer is disabled on iOS — the AVPlayer branch in
        // PlayerRouter is gone, so calling playerRouter.open() from here would either
        // re-enter TOS (the same embed that just failed) or be a no-op. Either way it
        // hides the error from the user. Just log; the YouTube IFrame renders its own
        // error UI inside the WKWebView. The user closes the player manually (back button
        // → tosState.minimize) and re-taps the video to retry the embed.
        //
        // TEST-ONLY: when `--uitesting-inline-tos` is in launch args, the helper
        // uses a direct SwiftUI `.overlay` instead of `landscapePlayerCover`'s UIKit
        // modal. The cover-present animation hides the WKWebView in the test
        // simulator long enough that YouTube's 5s player-config check times out
        // (error 153). The inline path is full-bleed and the WKWebView is visible
        // from frame 1.
        .landscapePlayerCover(item: tosFullScreenBinding, dismissStore: tosState) { video in
            TOSPlayerView(video: video, api: api) {
                // #158: YouTube's bot check asks to sign in inside the embed, which can't
                // work there. The standard player plays with the app's own sign-in, so
                // this one error still falls back to it on iOS.
                if tosState.vm?.playerError == .signInRequired {
                    rootLog.notice("[RootView] TOS sign-in required for videoId=\(video.id) — opening the standard player")
                    tosState.markFallback(videoId: video.id)
                    playerRouter.open(video: video, api: api)
                    return
                }
                rootLog.notice(
                    "[RootView] TOS onFallback for videoId=\(video.id) — AVPlayer disabled, not routing away. User must close + re-tap to retry."
                )
            }
        }
        .onChange(of: browseVM.deepLinkedVideo) { _, video in
            guard let video else { return }
            playerRouter.open(video: video, api: api)
            browseVM.deepLinkedVideo = nil
        }
        // UI-testing only: invisible button that re-opens the deeplink video in the
        // same session after stop() so testSecondOpenAfterStopPlays can verify the fix.
        // Uses the same browseVM.deepLinkedVideo path as the production deeplink, so
        // the full playerRouter.open() code path is exercised.
        .overlay(alignment: .bottomLeading) {
            let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
            let deeplinkArg = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--uitesting-deeplink-video=") })
            let deeplinkID: String? =
                deeplinkArg.map {
                    let id = String($0.dropFirst("--uitesting-deeplink-video=".count))
                    return id.isEmpty ? nil : id
                } ?? nil
            if isUITesting, let id = deeplinkID,
                playerState.presentation == .hidden, tosState.presentation == .hidden
            {
                Button {
                    browseVM.deepLinkedVideo = Video(id: id, title: "", channelTitle: "")
                } label: {
                    Color.clear.frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("uitesting.reopenDeeplinkVideoButton")
            }
        }
        .fullScreenCover(isPresented: $showSrcSwapSpike) {
            ShortsEmbedSrcSwapSpikeView()
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-shorts-srcswap-spike") {
                showSrcSwapSpike = true
            }
        }
        #endif
    }
}

// MARK: - MainTVTabView  (tvOS)
// Top-bar TabView is the Apple-recommended navigation pattern for Apple TV.
// Each tab contains a NavigationStack so drill-down is available within each section.

#if os(tvOS)
struct MainTVTabView: View {
    @State private var searchVM = SearchViewModel()
    @State private var selectedTab: AppSection = .home
    @Environment(\.innerTubeAPI) private var api

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppSection.allCases) { section in
                NavigationStack { section.destination(api: api) }
                    .tabItem {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                    .tag(section)
            }
        }
        .environment(searchVM)
    }
}
#endif

// MARK: - MainSidebarView  (macOS)

struct MainSidebarView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @State private var searchVM = SearchViewModel()

    @State private var selectedSection: AppSection? = .home
    /// Set when the IFrame player hits a fatal embed error on the current video so we
    /// drop through to the standard PlayerView for that video only. Cleared when the
    /// video changes.
    @State private var tosPlayerFallbackVideoId: String? = nil

    var body: some View {
        @Bindable var browseVM = browseVM
        ZStack {
            NavigationSplitView {
                List(AppSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .navigationTitle("SmartTube")
                if auth.isSignedIn {
                    Divider()
                    HStack {
                        AsyncImage(url: auth.accountAvatarURL) { img in
                            img.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        Text(auth.accountName ?? "Account")
                            .font(.subheadline)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            } detail: {
                NavigationStack { (selectedSection ?? .home).destination(api: api) }
            }
            .environment(searchVM)

            // Full-window player overlay — avoids macOS sheet coordinate issues that
            // prevent XCUITest click events from reaching controls inside a popover window.
            if let video = browseVM.deepLinkedVideo {
                #if os(macOS)
                let shouldUseTOS =
                    store.settings.useTOSPlayerOnMac
                    && tosPlayerFallbackVideoId != video.id
                if shouldUseTOS {
                    // TOS-compliant IFrame player experiment (macOS only, opt-in).
                    // Falls back to the standard PlayerView on embedding-disabled videos.
                    TOSPlayerView(video: video, api: api) {
                        // Mark this video ID so the guard above drops to PlayerView.
                        tosPlayerFallbackVideoId = video.id
                    }
                    .environment(store)
                    .environment(auth)
                    .environment(browseVM)
                    .ignoresSafeArea()
                } else {
                    PlayerView(video: video, api: api)
                        .environment(store)
                        .environment(auth)
                        .environment(browseVM)
                        .ignoresSafeArea()
                }
                #else
                PlayerView(video: video, api: api)
                    .environment(store)
                    .environment(auth)
                    .environment(browseVM)
                    .ignoresSafeArea()
                #endif
            }
        }
        // When a different video is opened, clear the per-video fallback guard so
        // the next video gets a fresh attempt through the TOS player.
        .onChange(of: browseVM.deepLinkedVideo?.id) { _, newId in
            if newId != tosPlayerFallbackVideoId {
                tosPlayerFallbackVideoId = nil
            }
        }
    }
}
