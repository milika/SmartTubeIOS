import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

extension ShortsPlayerView {

    // MARK: - Lifecycle

    func handleAppear() {
        if let video = currentVideo {
            if vm.currentVideoId == video.id {
                // Back from a pushed channel page / another tab (e.g. Settings).
                #if os(iOS)
                vm.syncSettings(store.settings)
                #else
                vm.updateSettings(store.settings)
                #endif
                if mode == .tab {
                    willResume()
                    vm.resume()
                } else if vm.wasPlayingBeforeSuspend {
                    vm.resume()
                }
            } else {
                loadVideo(at: currentIndex)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
            vm.showControls()
            vm.cancelControlsHide()
        }
        guard allowsFeedFetching else { return }
        Task { @MainActor in
            await feed.start()
            await feed.loadMoreIfNeeded(currentIndex: currentIndex)
        }
    }

    /// The feed appended Shorts: start playback if this is the first one (seedless
    /// feed), or continue an auto-scroll that was waiting at the end of the list.
    func handleFeedGrew(from oldCount: Int, to newCount: Int) {
        guard newCount > oldCount else { return }
        if oldCount == 0 {
            currentIndex = 0
            loadVideo(at: 0)
            return
        }
        #if os(iOS)
        if vm.videoEnded, store.settings.shortsAutoScroll, currentIndex + 1 < newCount, !isTransitioning {
            performVerticalTransition(direction: -1) { goTo(currentIndex + 1) }
        }
        #endif
    }

    // MARK: - Navigation

    /// Swipe up (`toNext`) / down. At the top, springs back; at the bottom, springs
    /// back while the feed fetches more.
    func swipe(toNext: Bool) {
        guard !isTransitioning else { return }
        if let target = ShortsNavigation.targetIndex(
            vertical: toNext ? -100 : 100, horizontal: 0, current: currentIndex, count: videos.count)
        {
            performVerticalTransition(direction: toNext ? -1 : 1) { goTo(target) }
        } else {
            cancelPageDrag()
            if toNext { loadMoreIfNeeded() }
        }
    }

    /// Programmatic page change (auto-scroll, error skip, tvOS remote): the same
    /// slide as a committed swipe — see `commitPage(direction:velocity:action:)`.
    func performVerticalTransition(direction: CGFloat, action: @escaping () -> Void) {
        commitPage(direction: direction, action: action)
    }

    func goTo(_ index: Int) {
        guard index >= 0, index < videos.count else { return }

        #if os(iOS)
        // The standby-swap/previous-swap "hot paths" (#271/#272/#274/#277) promoted a
        // pre-warmed VM by moving its WKWebView from a hidden/off-screen container
        // into the visible one (`vm = readyStandby` / `vm = readyPrevious`, which
        // retargets ShortsTOSWebView and triggers a UIKit reparent). Confirmed on a
        // physical device (#279): that reparent reliably leaves the screen solid
        // black afterward — brightness=0 — even though decode is completely correct
        // underneath (readyState=4, zero errors in the [diag] log) the whole time.
        // Three independent fixes were tried (forcing a fresh layout + isHidden
        // toggle nudge, positioning the hidden hosts off-screen at full opacity
        // instead of near-zero opacity, explicitly deactivating stale Auto Layout
        // constraints from the old superview before reparenting) — none changed the
        // outcome. Isolated by temporarily disabling just this hot path: with every
        // swipe forced through the plain loadVideo(at:) fallback below (same
        // WKWebView, never reparented — just an iframe-src swap), all 4 checks in
        // ShortsVisualPlaybackUITests.testHomeFirstShortPlaysAcrossThreeSwipes
        // rendered correctly (real brightness, no black frames) with no measurable
        // slowdown. Reparenting a WKWebView between view-hierarchy positions is not
        // reliable here — disabled permanently rather than continuing to chase a
        // UIKit/WebKit-level fix for a problem the simpler fallback path doesn't have.
        currentIndex = index
        loadVideo(at: index)
        #else
        currentIndex = index
        loadVideo(at: index)
        #endif

        isTitleExpanded = false
        loadMoreIfNeeded()
        // Pre-fetch the next 2 shorts so swiping is instant.
        let lookahead = videos[(index + 1)..<min(index + 3, videos.count)].map(\.id)
        if !lookahead.isEmpty {
            let token = authService.accessToken
            let cats = store.settings.activeSponsorCategories
            Task(priority: .background) {
                for videoId in lookahead {
                    await VideoPreloadCache.shared.prefetch(
                        videoId: videoId,
                        sponsorCategories: cats,
                        authToken: token,
                        priority: .speculative
                    )
                }
            }
        }
        // prewarmStandby(for:) is no longer called — see the long comment above in
        // the #if os(iOS) block of this function. Pre-warming a standby WKWebView
        // that's never actually promoted (the promotion path is disabled) would
        // just burn CPU/battery/memory decoding video nobody sees. The function and
        // its supporting VM infrastructure (isStandby/activate/loadShortAsStandby)
        // are left in place, unused, in case the underlying WKWebView-reparenting
        // bug is ever fixed and this is revisited. See #279.
    }

    #if os(iOS)
    /// Loads Short at `currentIndex + 1` into a background `ShortsEmbedPlayerViewModel`
    /// so it reaches `isReady == true` before the user swipes. `goTo(_:)` checks the
    /// standby and swaps it in immediately if ready — see Task #272.
    private func prewarmStandby(for index: Int) {
        let nextIndex = index + 1
        guard nextIndex < videos.count else {
            standbyVM = nil  // end of feed — no next Short to pre-warm
            return
        }
        let nextVideo = videos[nextIndex]
        // Defer construction to the next run loop turn. `ShortsEmbedPlayerViewModel
        // .init()` synchronously builds a full WKWebView (config, content
        // controller, 3 injected user scripts) — expensive enough on a physical
        // device to measurably delay the JUST-promoted video's own resume (its
        // webview reparenting + restarted JS poll loop), since `prewarmStandby`
        // used to run inline in the same `goTo()` call stack as `vm.activate()`.
        // Device-log confirmed: ~1.46s between "[goTo] standby swap" and the
        // promoted video's first post-promotion tick — far more than the JS poll
        // loop's 250ms interval alone would explain. See #276.
        Task { @MainActor in
            let standby = ShortsEmbedPlayerViewModel(api: api)
            standby.updateSettings(store.settings)
            // Attach to the view hierarchy immediately (ShortsPlayerView hosts
            // standbyVM in a hidden ShortsTOSWebView) — an unattached WKWebView
            // never progresses past readyState 0 (WebKit throttles media loading
            // the same way it does for a backgrounded tab), so the embed must be
            // mounted BEFORE loadShortAsStandby starts polling for isReady, not
            // after. See #274.
            standbyVM = standby
            shortsLog.notice(
                "[prewarm] starting — \(standby.logTag, privacy: .public) nextVideo=\(nextVideo.id, privacy: .public) forIndex=\(index, privacy: .public)"
            )
            await standby.loadShortAsStandby(video: nextVideo)
            if currentIndex == index {
                shortsLog.notice(
                    "[prewarm] standby ready — \(standby.logTag, privacy: .public) nextVideo=\(nextVideo.id, privacy: .public) isReady=\(standby.isReady, privacy: .public)"
                )
            } else {
                shortsLog.notice(
                    "[prewarm] standby discarded — \(standby.logTag, privacy: .public) user already moved past index \(index, privacy: .public)"
                )
            }
        }
    }
    #endif

    /// Asks the feed for the next page when the current Short is near the end.
    func loadMoreIfNeeded() {
        guard allowsFeedFetching else { return }
        let index = currentIndex
        Task { @MainActor in await feed.loadMoreIfNeeded(currentIndex: index) }
    }

    /// Overlay metadata for the current Short and the next one (so the rail is
    /// already filled in after a swipe).
    func loadMetadata(around index: Int) {
        guard allowsFeedFetching else { return }
        let ids = videos[index..<min(index + 2, videos.count)].map(\.id)
        let signedIn = authService.isSignedIn
        Task { @MainActor in
            for id in ids {
                await feed.loadMetadata(for: id, signedIn: signedIn)
                // Reel entries have no channel until their metadata arrives, so
                // "Don't recommend channel" can only catch them now.
                feed.removeHiddenChannels(after: currentIndex)
            }
        }
    }

    func loadVideo(at index: Int) {
        guard videos.indices.contains(index) else { return }
        let video = videos[index]
        loadMetadata(around: index)
        CrashlyticsLogger.setIntendedVideo(id: video.id, title: video.title)
        #if os(iOS)
        vm.updateSettings(store.settings)
        vm.loadShort(video: video)
        #else
        vm.load(video: video)
        vm.setPlaybackSpeed(store.settings.playbackSpeed)
        vm.updateSettings(store.settings)
        #endif
    }

    #if os(iOS)

    // MARK: - End of video / error recovery (iOS)

    /// Called from `.onChange(of: vm.playerState)` when the embed reports `.ended`:
    /// loop or auto-scroll per `settings.shortsAutoScroll` (`ShortsEndOfVideoDecision`).
    func handleShortEnded() {
        switch ShortsEndOfVideoDecision.decide(
            settings: store.settings, currentIndex: currentIndex, count: videos.count)
        {
        case .replay:
            vm.seekTo(0)
            vm.play()
        case .advance(let next):
            performVerticalTransition(direction: -1) { goTo(next) }
        case .freeze:
            // Auto-scroll is on but the feed hasn't delivered the next Short yet —
            // handleFeedGrew(from:to:) advances as soon as it does.
            vm.videoEnded = true
            loadMoreIfNeeded()
        }
    }

    /// Per the design spec's Error Handling section: on a per-Short load failure or
    /// "ready" timeout, log it and auto-advance to the next Short after a brief
    /// delay (so the error banner is visible), mirroring swipe-up. If there's no
    /// next Short, freeze like a natural end.
    func advanceAfterError() {
        guard let error = vm.playerError, error.isFatal else { return }
        let erroredVideoId = vm.currentVideoId
        logEmbedLoadError(error, videoId: erroredVideoId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard vm.currentVideoId == erroredVideoId, !isTransitioning else { return }
            if let next = ShortsNavigation.targetIndex(
                vertical: -100, horizontal: 0, current: currentIndex, count: videos.count)
            {
                performVerticalTransition(direction: -1) { goTo(next) }
            } else {
                vm.videoEnded = true
            }
        }
    }

    /// Logs a Shorts embed load failure via Crashlytics — mirrors the stall-logging
    /// pattern at PlaybackViewModel+Loading.swift:938 (bug #193), giving visibility
    /// into real-world embed failure rates per the design spec's Error Handling
    /// section.
    private func logEmbedLoadError(_ error: TOSPlayerError, videoId: String) {
        let reason: String
        switch error {
        case .notFound: reason = "notFound"
        case .embeddingDisabled: reason = "embeddingDisabled"
        case .iframeError(let code): reason = "iframeError(\(code))"
        case .webViewLoadFailed: reason = "readyTimeout"
        case .signInRequired: reason = "signInRequired"
        }
        let nsError = NSError(
            domain: "SmartTube.ShortsEmbedLoadFailure",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Shorts embed load failure: \(reason) (video \(videoId))"]
        )
        CrashlyticsLogger(category: "ShortsPlayer").recordNonFatal(
            nsError,
            userInfo: [
                "video_id": videoId,
                "reason": reason,
            ])
    }

    #endif
}
