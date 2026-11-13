import AVFoundation
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ShortsPlayerView
//
// Full-screen vertical-swipe player for YouTube Shorts, styled after the official
// app: action rail on the right, channel/title panel bottom-left, thin progress
// bar at the bottom. Swipe up advances to the next Short; swipe down goes back.
// The list comes from `ShortsFeedViewModel` — YouTube's own Shorts sequence,
// personalised when signed in.
//
// Touch routing: WKWebView swallows UIKit touches before SwiftUI sees them, so a
// UIViewRepresentable (`SwipeGestureOverlay`) installs pan/tap recognizers on the
// window. Those would also see touches on the overlay's buttons, so the overlay
// reports its controls' frames (`ShortsInteractiveFramesKey`) and the recognizers
// skip touches inside them, and are disabled while a sheet is up.

/// Where the Shorts player lives.
public enum ShortsPlayerMode: Sendable {
    /// Full-screen cover over another screen: own NavigationStack, back button, no tab bar.
    case presented
    /// Root of the Shorts tab: the tab's NavigationStack, tab bar visible, no back button.
    case tab
}

public struct ShortsPlayerView: View {
    let mode: ShortsPlayerMode
    /// Tab mode only: true while another player covers the tab (pause the Short).
    let isSuspended: Bool
    @State var feed: ShortsFeedViewModel
    #if os(iOS)
    /// The live Short's player plus its preloaded neighbours (see ShortsPlayerPool).
    @State var pool: ShortsPlayerPool
    #else
    @State var vm: PlaybackViewModel
    #endif
    @State var currentIndex: Int
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(SettingsStore.self) var store
    @Environment(AuthService.self) var authService
    @Environment(\.openURL) var openURL
    /// Vertical drag/slide of the pager (0 = at rest). See ShortsPlayerView+Pager.
    @State var slideOffset: CGFloat = 0
    @State var pageHeight: CGFloat = 0
    @State var isTransitioning = false
    /// True while the app is backgrounded — guards onDisappear from calling stop()
    /// when iOS fires it as a side-effect of backgrounding rather than navigation.
    @State var isInBackground = false

    // Overlay state
    @State var activeSheet: ShortsSheet?
    @State var isSharing = false
    @State var showSignIn = false
    @State var isTitleExpanded = false
    @State var scrubProgress: Double?
    @State var channelDestination: ChannelDestination?
    @State var interactiveFrames: [CGRect] = []
    @State var playerFrame: CGRect = .zero
    /// "Clear Screen" from the ⋯ menu: overlay hidden until the next tap.
    @State var isScreenCleared = false
    @State var showSearch = false
    /// The Short was playing when a pushed page (channel, search) covered the player;
    /// it resumes on return. Not `vm.wasPlayingBeforeSuspend`, which
    /// `handleForeground()` would act on while the pushed page is still on screen.
    @State var resumeOnReappear = false
    /// Another tab or a pushed page covers the player (set where it stops on
    /// disappearing, cleared on appearing).
    @State var isOffScreen = false
    /// Short confirmation shown over the player ("Saved to Watch Later").
    @State var toastMessage: String?
    #if os(iOS)
    /// The Short ended under a sheet with auto-scroll on: it replays until the sheet
    /// closes, then the feed moves on. Cleared when another Short is shown.
    @State var advancesWhenOverlayCloses = false
    #endif
    #if os(iOS)
    @State var captions: ShortsCaptionsController
    #endif

    let api: InnerTubeAPI
    /// Tab mode: runs right before the Short resumes on reappearing (back from a
    /// pushed page or another tab), so the tab can close other players first.
    let willResume: @MainActor () -> Void

    public init(
        source: ShortsFeedViewModel.Source,
        api: InnerTubeAPI,
        mode: ShortsPlayerMode = .presented,
        isSuspended: Bool = false,
        willResume: @escaping @MainActor () -> Void = {}
    ) {
        self.api = api
        self.mode = mode
        self.isSuspended = isSuspended
        self.willResume = willResume
        let feed = ShortsFeedViewModel(source: source, provider: api)
        self._feed = State(initialValue: feed)
        self._currentIndex = State(initialValue: feed.startIndex)
        #if os(iOS)
        self._pool = State(initialValue: ShortsPlayerPool(api: api))
        self._captions = State(initialValue: ShortsCaptionsController(api: api))
        #else
        self._vm = State(initialValue: PlaybackViewModel(api: api))
        #endif
    }

    var videos: [Video] { feed.videos }

    #if os(iOS)
    /// The player showing the current Short.
    var vm: ShortsEmbedPlayerViewModel { pool.live }
    #endif

    var currentVideo: Video? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }

    /// Hermetic UI tests page through fixed stub lists; never hit the network for more.
    var allowsFeedFetching: Bool {
        mode == .tab || !ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    /// The tab bar must stay usable in tab mode, so the player stops above it there.
    private var ignoredEdges: Edge.Set { mode == .tab ? .top : .all }

    /// A sheet, the share sheet or sign-in is up over the (still playing) Short. Their
    /// actions target `currentVideo`, so auto-scroll and error skips hold until it closes.
    var isOverlayPresented: Bool {
        activeSheet != nil || isSharing || showSignIn
    }

    /// Window-level gestures are off while anything is presented over the player.
    private var gesturesEnabled: Bool {
        !isOverlayPresented && channelDestination == nil && !showSearch
    }

    /// The comments/description sheet is up: the video shrinks into the space above it.
    var isVideoShrunk: Bool { activeSheet?.shrinksVideo == true }

    public var body: some View {
        switch mode {
        case .presented:
            NavigationStack { player }
        case .tab:
            player
        }
    }

    private var player: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            // The video sits below the status bar (or, with Fill Screen, behind it)
            // and runs down to the progress bar (see ShortsVideoLayout).
            GeometryReader { geo in
                let layout = ShortsVideoLayout(
                    pageFrame: geo.frame(in: .global), controlsFrame: playerFrame,
                    fillsScreen: store.settings.shortsFillScreen)
                let scale = isVideoShrunk ? shrunkScale(height: layout.box.height) : 1
                ZStack {
                    Color.clear.allowsHitTesting(false)
                    // One web view per pool slot, each fixed in place for its whole life;
                    // paging only moves them (see ShortsPlayerPool).
                    ForEach(pool.players.indices, id: \.self) { slot in
                        ShortsTOSWebView(vm: pool.players[slot])
                            .frame(width: layout.videoSize.width, height: layout.videoSize.height)
                            .frame(width: layout.box.width, height: layout.box.height)
                            .clipped()
                            .offset(
                                y: layout.boxCenterOffset
                                    + slotOffset(for: pool.players[slot], pageHeight: geo.size.height)
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    // Posters over pages whose video has no frame on screen yet.
                    pagePosters(layout: layout)
                    captionLayer(layout: layout)
                }
                // Neighbour pages sit just outside the page; in the Shorts tab the page
                // ends above the tab bar, so without this the next Short's top edge
                // shows under the tab bar.
                .clipped()
                // Shrunk above a sheet, the video's top edge (not the page's, which
                // runs under the status bar) lands at `shrunkTopInset`.
                .scaleEffect(scale, anchor: .top)
                .offset(y: isVideoShrunk ? shrunkTopInset - layout.box.minY * scale : 0)
                .animation(ShortsPaging.shrinkAnimation, value: isVideoShrunk)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                pageHeight = $0
            }
            .ignoresSafeArea(.all, edges: ignoredEdges)
            #else
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                Color.black.ignoresSafeArea()
            } else {
                #if os(tvOS)
                // A bare AVPlayerLayer (not VideoPlayer) so UIKit accessibility doesn't
                // hide the overlaid SwiftUI elements.
                PlayerAVLayerView(player: vm.player, videoGravity: .resizeAspectFill)
                    .offset(y: slideOffset)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                #else
                Color.black.ignoresSafeArea()
                #endif
            }
            #endif

            #if os(iOS)
            SwipeGestureOverlay(
                onSwipeUp: { swipe(toNext: true) },
                onSwipeDown: { swipe(toNext: false) },
                onTap: { _ in
                    if isScreenCleared {
                        withAnimation(.easeInOut(duration: 0.2)) { isScreenCleared = false }
                    } else if isTitleExpanded {
                        withAnimation(.easeInOut(duration: 0.2)) { isTitleExpanded = false }
                    } else {
                        vm.togglePlayPause()
                    }
                },
                onTwoFingerTap: {},
                onPanChanged: { dy in handlePanChanged(dy) },
                onSwipeCancelled: { cancelPageDrag() },
                onPanEnded: { dy, velocity in handlePanEnded(translation: dy, velocity: velocity) },
                isEnabled: gesturesEnabled,
                shouldHandleTouch: { point in shouldHandleTouch(at: point) }
            )
            .ignoresSafeArea(.all, edges: ignoredEdges)
            .accessibilityHidden(true)
            #endif

            if videos.isEmpty {
                emptyState
            }

            #if !os(iOS)
            if vm.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                    if let msg = vm.retryStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            if vm.statsForNerdsVisible {
                StatsForNerdsOverlay(snapshot: vm.statsSnapshot)
            }
            #endif
        }
        .background(Color.black.ignoresSafeArea())
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            playerFrame = $0
        }
        #if os(tvOS)
        // Siri Remote D-pad: up/down navigate prev/next short.
        .onMoveCommand { direction in
            switch direction {
            case .up: swipe(toNext: true)
            case .down: swipe(toNext: false)
            default: vm.toggleControls()
            }
        }
        #endif
        // Overlays sit outside the ZStack so the UIViewRepresentable gesture layer
        // can't absorb them from the accessibility tree.
        .overlay(alignment: .topTrailing) { indexBadge }
        .overlay {
            if !isScreenCleared && !isVideoShrunk {
                neighbourInfoPanels
                    .clipShape(ShortsPageBottomClip())
            }
        }
        .overlay {
            if shouldShowControlsOverlay {
                shortsOverlay
                    .offset(y: slideOffset)
                    .ignoresSafeArea(.keyboard)
                    .clipShape(ShortsPageBottomClip())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.Shorts.controlsOverlay)
            }
        }
        .overlay { errorBanner }
        #if !os(tvOS)
        .overlay(alignment: .top) { toast }
        #endif
        .onPreferenceChange(ShortsInteractiveFramesKey.self) { interactiveFrames = $0 }
        #if os(iOS)
        .navigationBarHidden(true)
        .statusBarHidden(mode == .presented)
        .modifier(ShortsTabBarStyle(mode: mode))
        #endif
        .navigationDestination(item: $channelDestination) { destination in
            ChannelView(channelId: destination.channelId)
        }
        .navigationDestination(isPresented: $showSearch) { SearchView() }
        #if !os(tvOS)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .comments:
                if let video = currentVideo {
                    ShortsCommentsSheet(
                        videoId: video.id,
                        commentCountText: feed.metadata[video.id]?.commentCountText,
                        api: api)
                }
            case .more:
                ShortsMoreSheet(
                    isSignedIn: authService.isSignedIn, hasChannel: currentMetadata?.channelId != nil
                ) { action in
                    handleMenuAction(action)
                }
            case .description:
                if let video = currentVideo {
                    ShortsDescriptionSheet(videoId: video.id, fallback: currentMetadata, api: api) { channelId in
                        activeSheet = nil
                        openChannel(channelId)
                    }
                }
            case .saveToPlaylist:
                if let video = currentVideo {
                    PlaylistPickerSheet(
                        mode: .save, video: video, sourcePlaylistId: nil, api: api,
                        onFinished: handleSavedToPlaylist)
                }
            }
        }
        #endif
        .sheet(isPresented: $showSignIn) { SignInView() }
        .onAppear(perform: handleAppear)
        .onDisappear {
            // Sheets and the share sheet keep the Short playing, like the official app.
            guard !isInBackground, !isOverlayPresented else { return }
            #if os(iOS)
            // A Short still loading would have started on its own.
            resumeOnReappear = vm.isPlaying || vm.isStarting
            #else
            resumeOnReappear = vm.isPlaying
            #endif
            isOffScreen = true
            vm.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                isInBackground = true
                vm.handleBackground()
            case .active:
                isInBackground = false
                vm.handleForeground()
            default:
                break
            }
        }
        .onChange(of: feed.videos.count) { oldCount, newCount in
            handleFeedGrew(from: oldCount, to: newCount)
        }
        .onChange(of: isSuspended) { _, suspended in
            if suspended {
                vm.stop()
            } else if !isOffScreen {
                #if os(iOS)
                vm.endStop()
                #endif
            }
        }
        #if os(iOS)
        .onChange(of: vm.playerState) { _, newState in
            if newState == .ended {
                handleShortEnded()
            }
        }
        // Keyed by video too: a swipe onto a preloaded Short that failed with the
        // same error as the previous one must still skip it.
        .onChange(of: LiveShortError(videoId: vm.currentVideoId, error: vm.playerError)) { _, new in
            if new.error != nil {
                advanceAfterError()
            }
        }
        .onChange(of: isOverlayPresented) { _, presented in
            if !presented { continueAutoScrollIfWaiting() }
        }
        .onChange(of: pageWindow.map(\.id)) { preloadNeighbours() }
        .onChange(of: vm.currentTime) { _, time in captions.update(time: time) }
        // Reel entries load before their metadata names the channel; hand it to the
        // player so SponsorBlock's channel exclusions apply.
        .onChange(of: currentVideo?.channelId) { _, channelId in
            guard let video = currentVideo else { return }
            pool.updateChannelId(channelId, for: video.id)
        }
        .onChange(of: currentVideo?.id, initial: true) { applyCaptions() }
        .onChange(of: store.settings.shortsCaptions) { applyCaptions() }
        .onChange(of: store.settings.playbackSpeed) { _, speed in
            pool.updateSettings(store.settings)
            vm.setPlaybackRate(speed)
        }
        #endif
    }

    private var shouldShowControlsOverlay: Bool {
        #if os(tvOS)
        vm.controlsVisible
        #else
        // Always visible like the official app, except in Clear Screen mode and while
        // the video is shrunk above a sheet.
        !videos.isEmpty && !isScreenCleared && !isVideoShrunk
        #endif
    }

    @ViewBuilder
    private var errorBanner: some View {
        #if os(iOS)
        if let msg = vm.errorMessage {
            bannerText(msg)
        }
        #else
        if let err = vm.error {
            bannerText(err.localizedDescription)
        }
        #endif
    }

    private func bannerText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(AccessibilityID.Shorts.errorBanner)
    }

    /// Seedless feed still loading, or nothing could be loaded.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            if let error = feed.loadError {
                Text("Couldn't load Shorts")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().tint(.white).scaleEffect(1.4)
            }
            if mode == .presented {
                backButton
            }
        }
        .foregroundStyle(.white)
        .padding(32)
        .accessibilityIdentifier(AccessibilityID.Shorts.emptyState)
    }

    /// `false` for touches the window-level recognizers must leave alone: outside the
    /// player (tab bar, sheets) or on an overlay control.
    private func shouldHandleTouch(at point: CGPoint) -> Bool {
        guard playerFrame == .zero || playerFrame.contains(point) else { return false }
        return !interactiveFrames.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }
}

#if os(iOS)
/// The live Short's error, tagged with the Short it belongs to.
private struct LiveShortError: Equatable {
    let videoId: String
    let error: TOSPlayerError?
}

/// Dark, always-visible tab bar while the Shorts tab is showing (official look).
private struct ShortsTabBarStyle: ViewModifier {
    let mode: ShortsPlayerMode

    func body(content: Content) -> some View {
        switch mode {
        case .presented:
            content.toolbar(.hidden, for: .tabBar)
        case .tab:
            content
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(Color.black, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
        }
    }
}
#endif
