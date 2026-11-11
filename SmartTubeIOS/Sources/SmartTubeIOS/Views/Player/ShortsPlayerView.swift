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
    @State var vm: ShortsEmbedPlayerViewModel
    /// Pre-warmed VM for Short N+1 — unused since #279 (see goTo(_:)); kept for that revisit.
    @State var standbyVM: ShortsEmbedPlayerViewModel? = nil
    /// The retired Short N-1 — unused since #279 (see goTo(_:)); kept for that revisit.
    @State var previousVM: ShortsEmbedPlayerViewModel? = nil
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
    /// Short confirmation shown over the player ("Saved to Watch Later").
    @State var toastMessage: String?
    #if os(iOS)
    @State var captions: ShortsCaptionsController
    #endif

    let api: InnerTubeAPI

    public init(
        source: ShortsFeedViewModel.Source,
        api: InnerTubeAPI,
        mode: ShortsPlayerMode = .presented,
        isSuspended: Bool = false
    ) {
        self.api = api
        self.mode = mode
        self.isSuspended = isSuspended
        let feed = ShortsFeedViewModel(source: source, provider: api)
        self._feed = State(initialValue: feed)
        self._currentIndex = State(initialValue: feed.startIndex)
        #if os(iOS)
        self._vm = State(initialValue: ShortsEmbedPlayerViewModel(api: api))
        self._captions = State(initialValue: ShortsCaptionsController(api: api))
        #else
        self._vm = State(initialValue: PlaybackViewModel(api: api))
        #endif
    }

    var videos: [Video] { feed.videos }

    var currentVideo: Video? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }

    /// Hermetic UI tests page through fixed stub lists; never hit the network for more.
    var allowsFeedFetching: Bool {
        mode == .tab || !ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    /// The tab bar must stay usable in tab mode, so the player stops above it there.
    private var ignoredEdges: Edge.Set { mode == .tab ? .top : .all }

    /// Window-level gestures are off while anything is presented over the player.
    private var gesturesEnabled: Bool {
        activeSheet == nil && !isSharing && !showSignIn && channelDestination == nil && !showSearch
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
            // Size the embed to its natural 9:16 aspect ratio and center it.
            GeometryReader { geo in
                let videoH = min(geo.size.height, geo.size.width * 16.0 / 9.0)
                ZStack {
                    Color.clear.allowsHitTesting(false)
                    ShortsTOSWebView(vm: vm)
                        .frame(width: geo.size.width, height: videoH)
                        .offset(y: slideOffset)
                        .accessibilityHidden(true)
                    // Unreachable since #279 (goTo(_:) never promotes these); kept off-screen
                    // for the day the WKWebView-reparenting bug is revisited.
                    if let standby = standbyVM {
                        ShortsTOSWebView(vm: standby)
                            .frame(width: geo.size.width, height: videoH)
                            .offset(y: geo.size.height * 3)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    if let previous = previousVM {
                        ShortsTOSWebView(vm: previous)
                            .frame(width: geo.size.width, height: videoH)
                            .offset(y: geo.size.height * 3)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    // Neighbour pages, and the live page's cover while its embed loads.
                    pagePosters(size: geo.size, videoHeight: videoH)
                    captionLayer(videoHeight: videoH)
                }
                .scaleEffect(isVideoShrunk ? shrunkScale(height: geo.size.height) : 1, anchor: .top)
                .offset(y: isVideoShrunk ? shrunkTopInset : 0)
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
            }
        }
        .overlay {
            if shouldShowControlsOverlay {
                shortsOverlay
                    .offset(y: slideOffset)
                    .ignoresSafeArea(.keyboard)
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
            guard !isInBackground, activeSheet == nil, !isSharing, !showSignIn else { return }
            vm.stop()
            #if os(iOS)
            previousVM?.stop()
            #endif
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
            if suspended { vm.stop() }
        }
        #if os(iOS)
        .onChange(of: vm.playerState) { _, newState in
            if newState == .ended {
                handleShortEnded()
            }
        }
        .onChange(of: vm.playerError) { _, newError in
            if newError != nil {
                advanceAfterError()
            }
        }
        .onChange(of: vm.currentTime) { _, time in captions.update(time: time) }
        .onChange(of: currentVideo?.id, initial: true) { applyCaptions() }
        .onChange(of: store.settings.shortsCaptions) { applyCaptions() }
        .onChange(of: store.settings.playbackSpeed) { _, speed in
            vm.updateSettings(store.settings)
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
