#if !os(tvOS)
import SwiftUI
import WebKit
import SmartTubeIOSCore
import os
#if os(iOS)
import UIKit
#endif

private let tosViewLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - TOSPlayerView
//
// YouTube IFrame embed player (macOS + iOS). Renders YouTube's own player
// chrome (controls:1) with a SponsorBlock skip toast overlaid on top.
//
// Dismissal:
//   macOS — Esc key (.onExitCommand). No on-screen button: every placement
//            attempt collided with macOS's OS-level titlebar chrome (traffic
//            lights, sidebar-toggle) which floats above the content view's
//            z-order — SwiftUI layout cannot steer clear of it from inside.
//   iOS   — Back button (top-left). Safe on iOS: full-screen modal has no
//            OS chrome above it. Back → TOSPlayerStateStore.minimize() so
//            audio continues in TOSMiniPlayerView.
//
// Entry path (macOS):
//   MainSidebarView (RootView.swift)
//     └─ store.settings.useTOSPlayerOnMac == true
//          └─ TOSPlayerView(video:api:)
//
// Entry path (iOS):
//   PlayerRouter.open(video:api:)
//     └─ store.useTOSPlayerOnIOS == true (always, by default — no user setting)
//          └─ TOSPlayerStateStore.play(video:api:) → .landscapePlayerCover
//               └─ TOSPlayerView(video:api:)
//
// When the IFrame player returns error 101/150 (embedding disabled) or 100
// (not found), `playerError.isFatal` is true and this view calls `onFallback`
// so the caller can show the standard PlayerView instead.

public struct TOSPlayerView: View {
    public let video: Video
    /// Called when the IFrame player hits a fatal error and we must fall back
    /// to the standard AVPlayer-based PlayerView.
    public var onFallback: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(BrowseViewModel.self) private var browseVM
    /// On macOS, the view owns the view model directly (no store — the player
    /// is a full-window overlay that is released when dismissed).
    @State private var vm: TOSPlayerViewModel
    #else
    /// On iOS, the view model is owned by TOSPlayerStateStore so it survives
    /// dismissal to mini-player. The view reads it from the environment.
    /// `tosState.vm` is optional — `stop()` sets it to nil while this view
    /// may still be mounted during a dismiss animation. `body` guards on it
    /// below and passes the unwrapped vm to all helper view-builders, so
    /// there is no force-unwrap anywhere in this file.
    @Environment(TOSPlayerStateStore.self) private var tosState
    #endif

    /// Drives `commentsOverlay` (see moreButton's Comments row). Plain view state —
    /// mirrors PlayerView.showCommentsSheet, but doesn't need to survive
    /// minimize-to-mini-player like the vm-owned properties above.
    @State private var showCommentsSheet = false

    #if os(iOS)
    /// Controls (back button, speed, more) are hidden on initial load and auto-hide
    /// after `controlsHideDelay` seconds when shown. A tap anywhere on the player
    /// reveals them; they auto-hide again after the delay.
    @State private var controlsVisible = false
    @State private var controlsHideTask: Task<Void, Never>? = nil
    private let controlsHideDelay: Double = 4
    /// User-forced landscape, independent of the device's physical rotation lock.
    /// See `tosPlayer.landscapeLockButton`'s doc comment.
    @State private var isLandscapeLocked = false

    private func showControls() {
        controlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(controlsHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }
    #endif

    public init(video: Video, api: InnerTubeAPI, onFallback: @escaping () -> Void = {}) {
        self.video = video
        self.onFallback = onFallback
        #if os(macOS)
        // startTime defaults to 0; saved position is restored asynchronously
        // in .task once the view has appeared (see body below).
        // `api` is threaded through so TOSPlayerViewModel can drive a WatchtimeTracker
        // (history/position-checkpoint parity with the standard PlayerView — see
        // TOSPlayerViewModel.saveProgress()).
        _vm = State(initialValue: TOSPlayerViewModel(videoId: video.id, title: video.title, channelId: video.channelId, channelTitle: video.channelTitle, thumbnailURL: video.thumbnailURL, startTime: 0, api: api))
        #endif
        // On iOS, TOSPlayerStateStore.play(video:api:) already created the vm
        // before presenting this view. Nothing to do here.
    }

    public var body: some View {
        // IMPORTANT: `.ignoresSafeArea()` must NOT be applied to this GeometryReader
        // (or anywhere in its modifier chain) — doing so makes `geo.safeAreaInsets`
        // report all-zero insets, which previously caused tosPlayer.backButton to
        // render under the status bar / Dynamic Island where XCUITest taps (and
        // real touches) never reach the SwiftUI view hierarchy. Instead, the
        // full-bleed black background and the WKWebView layer each call
        // `.ignoresSafeArea()` on themselves individually inside the ZStack below.
        // This keeps `geo.safeAreaInsets` reporting the real device insets — same
        // pattern as PlayerView+Lifecycle.swift's playerContentView and
        // PlayerControlsOverlay's `.padding(.top, max(safeAreaInsets.top, 20))`
        // (PlayerView+ControlElements).
        //
        // Why this matters here specifically: TOSPlayerView is presented as a
        // full-window ZStack overlay *inside* RootView's content view (see
        // RootView.body — `if let video = browseVM.deepLinkedVideo { TOSPlayerView(...) }`),
        // sitting alongside (not replacing) the NavigationSplitView. macOS draws the
        // window's titlebar/toolbar (traffic lights, sidebar toggle, back chevron,
        // "SmartTube" title) as OS-level chrome ABOVE the content view's z-order —
        // no amount of SwiftUI overlay/zIndex/.ignoresSafeArea() can cover it, because
        // it isn't part of the content view's layer at all. `safeAreaInsets.top` is
        // exactly the height SwiftUI reserves to avoid drawing under that chrome, so
        // anchoring topRightControls below it (instead of a flat offset that lands
        // those controls under/behind the sidebar-toggle and back-chevron controls)
        // keeps them clear of it.
        //
        // On iOS, `tosState.vm` can become nil (TOSPlayerStateStore.stop()) while
        // this view is still mounted during a dismiss-animation. Guard here and
        // render a black placeholder in that case — avoids a force-unwrap crash
        // (Crashlytics #259) in the AX-label overlay and everywhere else below.
        //
        // NOTE: there is intentionally NO on-screen back/close button here anymore —
        // every attempt at one (an "X" close button, then a back-chevron button)
        // ended up rendered in/near the OS-level titlebar chrome (traffic lights,
        // sidebar toggle) — the "strange position" complaint that kept resurfacing
        // no matter how the anchoring math was tuned, because that chrome floats
        // above the content view's z-order and isn't something SwiftUI layout can
        // reliably steer clear of from inside this view. Esc (.onExitCommand below)
        // is the dismissal path now — see its doc comment.
        #if os(iOS)
        guard let vm = tosState.vm else {
            return AnyView(Color.black.ignoresSafeArea())
        }
        #endif
        return AnyView(
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Full-bleed black background. `.ignoresSafeArea()` is applied to
                // this layer (and to the WKWebView layer below) individually —
                // NOT to the GeometryReader itself — so `geo.safeAreaInsets`
                // continues to report the real device insets (status bar /
                // Dynamic Island / home indicator), and non-ignoring children
                // below (topRightControls, backButton, sponsorToast) are laid
                // out with their origin already past that inset. topRightControls
                // additionally adds `geo.safeAreaInsets.top` to clear macOS's
                // titlebar chrome (see backButton's doc comment for why iOS must
                // NOT do the same). (Mirrors the working pattern in
                // PlayerView+Lifecycle.swift's playerContentView.)
                Color.black.ignoresSafeArea()

                // MARK: WKWebView layer
                YouTubeWebPlayerView(
                    webView: vm.webView,
                    externalDisplayOwnsWebView: ExternalDisplayManager.shared.owns(vm.webView),
                    onWindowReady: { [weak vm] in
                        // Defer the IFrame load until the WKWebView is actually
                        // in a visible window. The cover-present animation that
                        // brings the TOS player onto screen (triggered by the
                        // --uitesting-deeplink-video arg) sets the WKWebView's
                        // document.hidden=true while it animates in. YouTube's
                        // player-config check has a 5s server-side timeout; if
                        // the page is still hidden when the check runs, it
                        // times out → error 153 every time. Waiting for the
                        // window-ready callback ensures the IFrame loads
                        // against a visible page.
                        vm?.startIfNeededWhenWindowReady()
                    }
                )
                .ignoresSafeArea()

                #if os(iOS)
                // Keep WebKit visible for YouTube's player checks, but cover its
                // white startup paints with a video-appropriate background.
                if !vm.isReady {
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif

                #if os(macOS)
                // MARK: Top-right control cluster — more menu (like/dislike, sleep
                // timer, share) + playback speed picker. See topRightControls for why
                // these are native Menus rather than ports of the standard player's
                // custom overlay views. On iOS both live in the back-button row
                // instead (see backButton()) — there's no on-screen back button here
                // to anchor them to on macOS.
                topRightControls(topInset: geo.safeAreaInsets.top, vm: vm)
                #endif

                #if os(iOS)
                // MARK: Swipe-left/right navigation overlay (iOS only)
                // Mirrors PlayerSwipeGestureOverlay's left/right behaviour for the
                // AVPlayer pipeline. Restricted to the top portion of the screen so
                // YouTube's own bottom scrubber/control-bar drags are unaffected.
                TOSSwipeNavigationOverlay(
                    onSwipeLeft: { vm.playNext() },
                    onSwipeRight: { vm.playPrevious() },
                    onTap: { _ in
                        // #111 history: we tried to undo YouTube's tap-to-pause so that
                        // tapping to reveal controls wouldn't also pause playback. But the
                        // undo misfired on the user's first *intentional* pause (controls
                        // were hidden, user tapped to both show controls and pause — our
                        // code saw controlsWereVisible=false and undid it). Letting
                        // YouTube's native tap = toggle-play/pause stand is the correct
                        // behaviour: it matches YouTube's own app and is what users expect.
                        showControls()
                    },
                    // Its pan recognizer lives on the window, so it would also see a
                    // drag along the external-display scrubber drawn above it and turn
                    // a seek into a video change. Prev/next are buttons there.
                    isEnabled: !ExternalDisplayManager.shared.owns(vm.webView)
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

                // External display: the embed renders on the TV, so the local
                // container is empty. This sits above TOSSwipeNavigationOverlay so its
                // buttons receive taps instead of the gesture layer below.
                if ExternalDisplayManager.shared.owns(vm.webView) {
                    TOSExternalDisplayOverlay(vm: vm)
                }

                // MARK: Back button (iOS only)
                // Safe here — full-screen modal has no OS chrome above it. Tapping
                // minimizes to the mini-player so audio continues (unlike macOS where
                // Esc fully dismisses). A small fixed padding is enough to clear the
                // status bar — see backButton's doc comment for why `topInset` must
                // NOT be added here too.
                backButton(vm: vm)
                    // The overlay below covers the tap-to-reveal gesture layer, so the
                    // back button has to stay reachable on its own while it is up.
                    .opacity(controlsVisible || ExternalDisplayManager.shared.owns(vm.webView) ? 1 : 0)
                    .allowsHitTesting(controlsVisible || ExternalDisplayManager.shared.owns(vm.webView))
                #endif

                // MARK: SponsorBlock skip toast (bottom-centre)
                if let seg = vm.currentToastSegment {
                    sponsorToast(for: seg, vm: vm)
                }

                // MARK: Comments overlay (triggered from moreButton)
                if showCommentsSheet {
                    commentsOverlay(vm: vm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: showCommentsSheet)
                }
            }
        }
        // Invisible AX label exposing player state for UI tests.
        // Mirrors player.titleLabel / player.probeStreamResult on PlayerView.
        // foregroundColor(.clear) keeps the text in the AX tree with a readable
        // label while being visually transparent. opacity(0/0.001) and frame(1,1)
        // both cause macOS 26 AX to return an empty label.
        .overlay(alignment: .topTrailing) {
            Text(vm.playerState == .playing || vm.playerState == .buffering ? "playing"
                 : vm.playerState == .paused ? "paused"
                 : vm.playerState == .ended ? "ended" : "unstarted")
                .foregroundColor(.clear)  // visually invisible; AX still reads text
                .font(.caption2)
                .allowsHitTesting(false)
                .accessibilityIdentifier("tosPlayer.stateLabel")
                .accessibilityHidden(false)
        }
        .onAppear {
            vm.updateSettings(store.settings)
            // #51/#78: without this, WatchtimeTracker's pings carry no auth
            // header even for signed-in users, so playback through the TOS
            // player (the iOS default since 4.6) never registers in YouTube's
            // watch history — same root cause already fixed for PlaybackViewModel
            // in PlayerView+Lifecycle.swift, never ported to TOS.
            vm.updateAuthToken(authService.accessToken)
            vm.updateSAPISID(authService.sapisid)
            // The IFrame load is deferred to YouTubeWebPlayerView's window-ready
            // callback (see UIViewRepresentable Coordinator in this file), which
            // fires once the WKWebView is in a key window after the cover-present
            // animation has finished. Calling startIfNeededWhenWindowReady from
            // a Task @MainActor here was unreliable — the Task was being
            // cancelled by SwiftUI's re-render cycle before the sleep
            // completed. The window callback uses DispatchQueue.main.asyncAfter
            // inside the view model, which isn't subject to view-lifecycle
            // cancellation. startIfNeeded() (without "WhenWindowReady") is a
            // no-op fallback kept for safety in case the callback is missed.
            vm.startIfNeeded()
            #if os(iOS)
            // Show controls briefly on first appear so the back button is tappable
            // without the user having to tap the player area first. The 4s auto-hide
            // in showControls() then fades them out. Subsequent reveals happen via
            // the TOSSwipeNavigationOverlay tap or on videoId change.
            showControls()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let physicallyLandscape = UIDevice.current.orientation.isLandscape
            OrientationManager.shared.playerIsActive = isLandscapeLocked || store.settings.landscapeAlwaysPlay || physicallyLandscape
            #endif
        }
        // Pause the embedded <video> element when this view leaves the hierarchy.
        //
        // On macOS: fires on Esc or fallback — always pause + checkpoint.
        //
        // On iOS: fires both on minimize (→ mini-player, audio SHOULD continue)
        // and on full stop (TOSPlayerStateStore.stop() was called). We only pause
        // when the store says we're fully stopped (.hidden); TOSPlayerStateStore
        // .minimize() intentionally does NOT pause so audio keeps playing.
        // TOSPlayerStateStore.stop() calls vm.pause() itself before releasing the vm.
        //
        // saveProgress() mirrors the standard PlayerView's vm.suspend()/vm.stop() —
        // both of which checkpoint the watch position from the same onDisappear hook
        // (see PlayerView+Lifecycle.swift). Without it, closing a TOS-played video
        // silently lost the watch position (resume-from-last-position and "continue
        // watching"/history never worked for TOS sessions — see WatchtimeTracker).
        .onDisappear {
            #if os(iOS)
            controlsHideTask?.cancel()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            OrientationManager.shared.playerIsActive = false
            // On iOS, only pause when fully stopped — not when minimizing to mini-player.
            // TOSPlayerStateStore.stop() already calls vm.pause() + vm.saveProgress()
            // before releasing the vm, so we only log here in that case.
            guard tosState.presentation == .hidden else {
                tosViewLog.notice("[TOSPlayerView] onDisappear — minimizing to mini-player, audio continues (videoId=\(self.video.id, privacy: .public))")
                return
            }
            vm.cancel()
            tosViewLog.notice("[TOSPlayerView] onDisappear — fully stopped (videoId=\(self.video.id, privacy: .public)) — stop() already paused & checkpointed")
            #else
            tosViewLog.notice("[TOSPlayerView] onDisappear — videoId=\(self.video.id, privacy: .public) playerState=\(String(describing: vm.playerState), privacy: .public) currentTime=\(vm.currentTime, format: .fixed(precision: 1))s — pausing & checkpointing")
            vm.pause()
            vm.saveProgress()
            #endif
        }
        #if os(macOS)
        // Esc key closes the player. This is the ONLY dismissal path on macOS — every
        // on-screen back/close button tried so far ("X", then a back-chevron)
        // ended up rendered on/near the OS-level titlebar chrome (traffic lights,
        // sidebar toggle, native back chevron) no matter how its position was
        // anchored, because that chrome floats above the content view's z-order —
        // SwiftUI layout from inside this view simply can't steer reliably clear
        // of it. TOSPlayerView is presented as a conditional full-window overlay
        // (RootView: `if let video = browseVM.deepLinkedVideo`), not pushed onto a
        // NavigationStack, so the window's own titlebar "Back" chevron belongs to
        // the browse content underneath and does not affect this overlay at all —
        // Esc is genuinely the only way in.
        .onExitCommand {
            browseVM.deepLinkedVideo = nil
            dismiss()
        }
        #endif
        // Restore saved watch position asynchronously.
        // We seek once the player reports .playing or .paused (i.e. after onReady fires)
        // so the IFrame API is ready to accept seekTo() calls.
        .task {
            // Only on a fresh load. Re-appearing from the mini-player (where playback
            // kept running) must not rewind to the position saved when it minimized.
            guard vm.playerState == .unstarted else { return }
            let saved = await VideoStateStore.shared.state(for: video.id)?.position ?? 0
            guard saved > 1 else { return }
            // Poll briefly for player readiness before seeking.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard vm.isReady else { continue }
                vm.seekTo(saved)
                return
            }
        }
        // Watch for fatal IFrame errors → fall back to standard player.
        // Do NOT clear deepLinkedVideo here — RootView uses tosPlayerFallbackVideoId
        // (set by onFallback()) to switch from TOSPlayerView to PlayerView while
        // keeping deepLinkedVideo set so the standard player can open the same video.
        .onChange(of: vm.playerError) { _, error in
            guard let error else { return }
            tosViewLog.notice("[TOSPlayerView] playerError=\(String(describing: error)) isFatal=\(error.isFatal)")
            guard error.isFatal else { return }
            tosViewLog.notice("[TOSPlayerView] ⚠️ fatal error — triggering fallback to standard player")
            #if os(iOS)
            // This embed will never reach playback, so it can never take the external
            // screen over from its predecessor — release whatever is still shown there.
            ExternalDisplayManager.shared.withdrawAll()
            #endif
            onFallback()
        }
        #if os(iOS)
        // Show controls briefly whenever a new video loads via swipe navigation
        // (tosState.vm is replaced by TOSPlayerStateStore.play). Without this the
        // controls stay hidden if the user swiped while they were already hidden.
        .onChange(of: vm.videoId) { _, _ in showControls() }
        // Keep landscape advertised to UIKit in sync with physical rotation, the
        // shared "Landscape Always Play" setting, and the lock button — mirrors
        // PlayerView+Lifecycle.swift's identical orientation-sync modifiers.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            guard orientation.isValidInterfaceOrientation else { return }
            OrientationManager.shared.playerIsActive =
                isLandscapeLocked || store.settings.landscapeAlwaysPlay || orientation.isLandscape
        }
        .onChange(of: store.settings.landscapeAlwaysPlay) { _, alwaysLandscape in
            OrientationManager.shared.playerIsActive = isLandscapeLocked || alwaysLandscape
        }
        .onChange(of: isLandscapeLocked) { _, isLocked in
            OrientationManager.shared.playerIsActive = isLocked || store.settings.landscapeAlwaysPlay
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            vm.handleForeground()
        }
        #endif
        )
    }

    #if os(iOS)
    // MARK: - Back button (iOS only)
    //
    // Calls tosState.minimize() so audio continues in TOSMiniPlayerView —
    // unlike macOS's Esc which fully stops.
    //
    // Positioning: this view is placed inside the GeometryReader/ZStack in
    // `body`, which does NOT call `.ignoresSafeArea()` on itself — only the
    // full-bleed background and WKWebView layers opt out individually. That
    // means SwiftUI already constrains this view's layout to the safe area:
    // its origin (0,0) starts AT the safe-area boundary (i.e. just below the
    // status bar / Dynamic Island), with the inset amount reported separately
    // via `geo.safeAreaInsets`. A plain `.padding(.top, 8)` therefore lands
    // 8pt below the status bar — adding `geo.safeAreaInsets.top` on top of
    // that (as a previous version of this code did) double-counts the inset
    // and pushes the button ~60pt further down than intended, into the row
    // where the IFrame player's own channel-info overlay sits — which is the
    // "back button is too low and doesn't work" regression reported on-device.
    private func backButton(vm: TOSPlayerViewModel) -> some View {
        VStack {
            // Tighter spacing/padding than usual (4pt gaps, 9pt circle padding) —
            // with 4 items in this row (back, speed, more, lock) the wider defaults
            // pushed far enough right to crowd into the IFrame's own native
            // top-right icons (volume/CC/settings gear), especially on narrower
            // screens. This keeps the whole cluster more compact so there's a
            // visible gap before YouTube's own controls start.
            HStack(spacing: 4) {
                Button {
                    tosState.minimize()
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("tosPlayer.backButton")

                // Playback speed pill + more menu — placed here (rather than top-right)
                // so they don't overlap the IFrame's own video-title/channel row, which
                // sits just below the top-right corner.
                speedButton(vm: vm)
                moreButton(vm: vm)

                // Landscape lock — lets the user force landscape playback without
                // disabling their device's portrait orientation lock. Ported from
                // PlayerView+ControlElements.swift (the old AVPlayer pipeline) —
                // this was never carried over when TOS became the iOS default,
                // which is why it disappeared for users who had it before.
                Button {
                    isLandscapeLocked.toggle()
                } label: {
                    Image(systemName: isLandscapeLocked ? "lock.rotation" : "lock.rotation.open")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("tosPlayer.landscapeLockButton")

                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 16)
            Spacer()
        }
    }
    #endif

    // MARK: - Top-right control cluster (speed + more)
    //
    // Both rendered as native macOS `Menu`s rather than the standard player's custom
    // overlay+backdrop pickers / more-menu sheet: controls:1 leaves no "more menu"
    // affordance to anchor a picker sheet from, and a Menu needs no new
    // dismissal/animation/focus state of its own — it's the idiomatic macOS control
    // for "pick one of a short list", and a `Menu`-of-`Menu`s is itself a minimal,
    // zero-new-state stand-in for the "more menu" the architecture analysis flagged
    // as a prerequisite for richer transfers (queue, captions, description, etc.) —
    // this is the lightest possible version of that affordance, available today
    // without waiting on the controls:0 fork.
    #if os(macOS)
    private func topRightControls(topInset: CGFloat, vm: TOSPlayerViewModel) -> some View {
        HStack(spacing: 8) {
            Spacer()
            moreButton(vm: vm)
            speedButton(vm: vm)
        }
        .padding(.top, max(topInset, 16))
        .padding(.trailing, 16)
    }
    #endif

    /// Transferred from PlayerView+PickerOverlays.speedPickerOverlay — same source of
    /// truth (`AppSettings.availableSpeeds` / `store.settings.playbackSpeed`) and the
    /// same JS-bridge call (`vm.setPlaybackRate`). The displayed speed is
    /// `store.settings.playbackSpeed` (the user's selection) — `stateDetectionJS` has
    /// no `ratechange` listener, so there is no live rate to read back from the player.
    private func speedButton(vm: TOSPlayerViewModel) -> some View {
        Menu {
            ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                Button {
                    store.settings.playbackSpeed = speed
                    vm.setPlaybackRate(speed)
                } label: {
                    if abs(store.settings.playbackSpeed - speed) < 0.01 {
                        Label(speedLabel(for: speed), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(for: speed))
                    }
                }
            }
        } label: {
            Text(speedLabel(for: store.settings.playbackSpeed))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("tosPlayer.speedButton")
        .accessibilityLabel("Playback speed")
    }

    private func speedLabel(for speed: Double) -> String {
        speed == 1.0 ? "Normal (1\u{d7})" : String(format: "%.2g\u{d7}", speed)
    }

    // MARK: - More menu (Like/Dislike, Sleep Timer, Share, Comments)
    //
    // Transfer of self-contained, AVPlayer-independent standard-player features
    // that previously had zero presence in TOS:
    //   • Like/Dislike  — PlaybackViewModel+LikeDislike.swift: pure InnerTubeAPI calls
    //                     with optimistic update + rollback. Gated on sign-in, mirroring
    //                     moreMenuLikeDislikeRow's `if authService.isSignedIn` guard.
    //   • Sleep Timer   — PlaybackViewModel+SleepTimer.swift: schedules a Task that
    //                     calls player.pause(); TOS only needed vm.pause() to slot in.
    //   • Share         — pure metadata (no player dependency at all).
    //   • Comments      — PlayerView+Overlays.swift's commentsOverlay/loadComments:
    //                     pure InnerTubeAPI fetch, rendered via the shared
    //                     CommentRowView (PlayerView+AuxViews.swift).
    private func moreButton(vm: TOSPlayerViewModel) -> some View {
        Menu {
            #if os(iOS)
            if ExternalDisplayManager.shared.isScreenConnected {
                // Reflects the user's choice, not whether the embed is on the screen
                // right now: before playback starts nothing is shown there yet, and
                // the row must still offer the phone.
                let onExternal = ExternalDisplayManager.shared.userWantsExternal
                Button {
                    ExternalDisplayManager.shared.setUserWantsExternal(!onExternal)
                } label: {
                    Label(onExternal
                          ? String(localized: "Play on Phone", bundle: .module)
                          : String(localized: "Play on External Display", bundle: .module),
                          systemImage: onExternal ? "iphone" : "tv")
                }
                .accessibilityIdentifier("tosPlayer.moreMenu.externalDisplayRow")
            }
            #endif
            if authService.isSignedIn {
                Button {
                    vm.like()
                } label: {
                    Label(vm.likeStatus == .like ? "Liked" : "Like",
                          systemImage: vm.likeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .accessibilityIdentifier("tosPlayer.moreMenu.likeRow")

                Button {
                    vm.dislike()
                } label: {
                    Label(vm.likeStatus == .dislike ? "Disliked" : "Dislike",
                          systemImage: vm.likeStatus == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .accessibilityIdentifier("tosPlayer.moreMenu.dislikeRow")

                Divider()
            }

            Menu {
                Button {
                    vm.setSleepTimer(minutes: nil)
                } label: {
                    if vm.sleepTimerMinutes == nil {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                ForEach(PlaybackViewModel.sleepTimerOptions, id: \.self) { mins in
                    Button {
                        vm.setSleepTimer(minutes: mins)
                    } label: {
                        if vm.sleepTimerMinutes == mins {
                            Label("\(mins) minutes", systemImage: "checkmark")
                        } else {
                            Text("\(mins) minutes")
                        }
                    }
                }
            } label: {
                Label(sleepTimerLabel(vm: vm), systemImage: "moon.zzz")
            }
            .accessibilityIdentifier("tosPlayer.moreMenu.sleepTimerRow")

            if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("tosPlayer.moreMenu.shareRow")
            }

            Button {
                showCommentsSheet = true
                vm.loadComments()
            } label: {
                Label("Comments", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("tosPlayer.moreMenu.commentsRow")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(.ultraThinMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("tosPlayer.moreButton")
        .accessibilityLabel("More")
    }

    private func sleepTimerLabel(vm: TOSPlayerViewModel) -> String {
        guard let minutes = vm.sleepTimerMinutes else { return "Sleep Timer" }
        return "Sleep Timer (\(minutes)m)"
    }

    // MARK: - Comments overlay
    //
    // Transferred from PlayerView+Overlays.commentsOverlay — same dim-backdrop +
    // bottom-sheet layout and the same shared CommentRowView. tvOS-only bits
    // (focusScope/.onExitCommand) are dropped: TOSPlayerView is `!os(tvOS)`.
    private func commentsOverlay(vm: TOSPlayerViewModel) -> some View {
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false },
            accessibilityId: "tosPlayer.commentsOverlay"
        )
    }

    // MARK: - SponsorBlock toast

    private func sponsorToast(for segment: SponsorSegment, vm: TOSPlayerViewModel) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    vm.seekTo(segment.end)
                    vm.currentToastSegment = nil
                } label: {
                    Label(skipLabel(for: segment.category), systemImage: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 60)
            }
        }
        .accessibilityIdentifier("tosPlayer.skipToast")
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: vm.currentToastSegment?.start)
    }

    private func skipLabel(for category: SponsorSegment.Category) -> String {
        switch category {
        case .sponsor:       return "Skip Sponsor"
        case .selfPromo:     return "Skip Self-Promo"
        case .interaction:   return "Skip Interaction"
        case .intro:         return "Skip Intro"
        case .outro:         return "Skip Outro"
        case .preview:       return "Skip Preview"
        case .filler:        return "Skip Filler"
        case .musicOfftopic: return "Skip Music"
        case .poiHighlight:  return "Skip to Highlight"
        }
    }
}

// MARK: - YouTubeWebPlayerView (NSViewRepresentable)

/// Wraps the `WKWebView` owned by `TOSPlayerViewModel` in a platform view
/// so SwiftUI can host it. The view model owns the WKWebView instance;
/// this representable just displays it.
#if os(macOS)
private struct YouTubeWebPlayerView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.autoresizingMask = [.width, .height]
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
/// Hosts the WKWebView inside a container with Auto Layout constraints, mirroring
/// FullScreenPlayerLayerView's transplant pattern for PersistentPlayerHostView.
/// The webView is owned by TOSPlayerViewModel (which outlives this representable's
/// lifecycle), so when this view is dismissed and TOSMiniPlayerLayerView's container
/// calls addSubview(webView), UIKit automatically removes it from this container —
/// no explicit removeFromSuperview needed on dismiss. updateUIView re-attaches the
/// webView here if it was transplanted away and is now expanding back to full screen.
/// Shown in place of the embed while it lives on an external screen.
///
/// YouTube's own controls are part of the IFrame page, so they travel to the TV with
/// the web view. These native ones drive the same player through the JS bridge.
private struct TOSExternalDisplayOverlay: View {
    let vm: TOSPlayerViewModel

    /// Non-nil while the user drags the bar, or while a seek is still in flight.
    @State private var scrubTarget: Double?

    private var isPlaying: Bool {
        vm.playerState == .playing || vm.playerState == .buffering
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "tv")
                        .font(.system(size: 40))
                    Text(String(localized: "Playing on external display", bundle: .module))
                        .font(.callout)
                }
                .foregroundStyle(.white.opacity(0.6))

                transportRow
                progressRow
            }
            .padding(.horizontal, 32)
        }
        .overlay(alignment: .topTrailing) { topRightCluster }
        // Identified for UI tests as a container, so the buttons inside stay
        // reachable rather than being folded into one element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tosPlayer.externalDisplayOverlay")
    }

    /// Stands in for YouTube's own top-right cluster, which is part of the chrome
    /// hidden on the external screen. Same position and styling as the app's other
    /// player buttons; the settings gear is not reproduced because its menu opens
    /// inside the page — that is, on the TV, out of reach.
    private var topRightCluster: some View {
        HStack(spacing: 8) {
            iconButton(vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       id: "muteButton", label: vm.isMuted ? "Unmute" : "Mute") { vm.toggleMuted() }
            iconButton(vm.captionsOn ? "captions.bubble.fill" : "captions.bubble",
                       id: "captionsButton", label: "Captions") { vm.toggleCaptions() }
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    private func iconButton(_ systemName: String, id: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            tosViewLog.notice("[ExternalDisplay] panel tap — \(id, privacy: .public)")
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tosPlayer.externalDisplay.\(id)")
    }

    private var transportRow: some View {
        HStack(spacing: 28) {
            button("backward.end.fill", size: 22, id: "previousButton", label: "Previous") { vm.playPrevious() }
            button("gobackward.10", size: 26, id: "seekBackButton", label: "Back 10 seconds") {
                vm.seekTo(max(0, vm.currentTime - 10))
            }
            button(isPlaying ? "pause.fill" : "play.fill", size: 34, id: "playPauseButton",
                   label: isPlaying ? "Pause" : "Play") {
                if isPlaying { vm.pause() } else { vm.play() }
            }
            button("goforward.10", size: 26, id: "seekForwardButton", label: "Forward 10 seconds") {
                // Duration is 0 until the player reports it; clamping to it would rewind.
                let target = vm.currentTime + 10
                vm.seekTo(vm.duration > 0 ? min(vm.duration, target) : target)
            }
            button("forward.end.fill", size: 22, id: "nextButton", label: "Next") { vm.playNext() }
        }
    }

    @ViewBuilder
    private var progressRow: some View {
        let duration = max(vm.duration, 1)
        // While dragging, and until the player's reported time catches up with the
        // seek, the bar follows the finger instead of snapping back to the old time.
        let position = min(scrubTarget ?? vm.currentTime, duration)
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: width * (position / duration))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubTarget = seconds(at: value.location.x, width: width, duration: duration)
                        }
                        .onEnded { value in
                            let target = seconds(at: value.location.x, width: width, duration: duration)
                            scrubTarget = target
                            vm.seekTo(target)
                        }
                )
            }
            .frame(height: 24)
            .accessibilityIdentifier("tosPlayer.externalDisplay.scrubber")

            HStack {
                Text(timeLabel(position))
                Spacer()
                Text(timeLabel(vm.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .onChange(of: vm.currentTime) { _, now in
            // Hand the bar back to the player once it reports a time near the seek.
            if let target = scrubTarget, abs(now - target) < 1.5 { scrubTarget = nil }
        }
    }

    private func seconds(at x: CGFloat, width: CGFloat, duration: Double) -> Double {
        min(max(Double(x / width), 0), 1) * duration
    }

    private func button(_ systemName: String, size: CGFloat, id: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            tosViewLog.notice("[ExternalDisplay] panel tap — \(id, privacy: .public)")
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .padding(8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("tosPlayer.externalDisplay.\(id)")
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

private struct YouTubeWebPlayerView: UIViewRepresentable {
    let webView: WKWebView
    /// True while the external screen holds this web view. Passed in rather than read
    /// from the manager inside make/update, which are not observation-tracked.
    let externalDisplayOwnsWebView: Bool
    /// Fires when the container view is added to a visible window (i.e. the
    /// cover-present animation has finished and the WKWebView is actually
    /// on-screen). TOSPlayerView passes a closure that calls
    /// `vm.startIfNeededWhenWindowReady()` from here instead of from
    /// `.onAppear` — the .onAppear fires during the cover-present animation
    /// (while the WKWebView is still hidden), and YouTube's IFrame refuses
    /// to start its 5s player-config check against a hidden document (error
    /// 153 every time). Waiting for window-ready ensures the IFrame loads
    /// against a visible page.
    let onWindowReady: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onWindowReady: onWindowReady) }

    final class Coordinator: NSObject, @unchecked Sendable {
        let onWindowReady: (() -> Void)?
        private var observer: NSObjectProtocol?
        private let stateLock = NSLock()
        fileprivate var hasFired: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _hasFired }
        fileprivate func setHasFired(_ v: Bool) { stateLock.lock(); _hasFired = v; stateLock.unlock() }
        private var _hasFired = false
        init(onWindowReady: (() -> Void)?) {
            self.onWindowReady = onWindowReady
        }
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
        /// Called by the container view when it gets added to a window that
        /// is on-screen. The notification approach beats overriding
        /// `didMoveToWindow` because the container's own override would
        /// otherwise have to forward the call up the responder chain.
        func attach(to view: UIView) {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    // Only fire if the view is actually in the key window.
                    guard view.window?.isKeyWindow == true else { return }
                    if self.hasFired { return }
                    self.setHasFired(true)
                    self.onWindowReady?()
                }
            }
        }
    }

    func makeUIView(context: Context) -> UIView {
        tosViewLog.notice("[TOSView] YouTubeWebPlayerView.makeUIView called")
        let container = UIView()
        container.backgroundColor = .black
        // Skip while the external display holds this web view — updateUIView takes it
        // back once the screen is released.
        if !externalDisplayOwnsWebView {
            attach(to: container)
        }
        // No window-key notification observation here — the window is
        // already key when the WKWebView is added to it (the cover-present
        // animation runs in a key window, not a window that's about to
        // become key), so `UIWindow.didBecomeKeyNotification` never fires.
        // The 1.5s asyncAfter inside TOSPlayerViewModel.startIfNeededWhenWindowReady
        // is the actual delay that lets the cover-present complete before
        // loadEmbed runs.
        if let cb = onWindowReady {
            DispatchQueue.main.async { cb() }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if !externalDisplayOwnsWebView, webView.superview !== uiView {
            attach(to: uiView)
        }
        // No fire-from-here — the makeUIView async already schedules the
        // load, and updateUIView can fire before the view is actually visible
        // (the view is in a window but the cover-present animation is still
        // running, so document.hidden=true).
    }

    private func attach(to container: UIView) {
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
#endif

#endif // !os(tvOS)
