import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension ShortsPlayerView {

    // MARK: - Lifecycle

    func handleAppear() {
        let resumeOnReappear = resumeOnReappear
        self.resumeOnReappear = false
        isOffScreen = false
        #if os(iOS)
        // On screen again: Shorts that go live from now on play (see `vm.stop()`).
        vm.endStop()
        #endif
        if let video = currentVideo {
            if vm.currentVideoId == video.id {
                // Back from a pushed channel page / another tab (e.g. Settings).
                #if os(iOS)
                pool.syncSettings(store.settings)
                #else
                vm.updateSettings(store.settings)
                #endif
                if mode == .tab {
                    willResume()
                    vm.resume()
                } else if resumeOnReappear || vm.wasPlayingBeforeSuspend {
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
        continueAutoScrollIfWaiting()
        #endif
    }

    #if os(iOS)
    /// Advances past a Short that ended (or failed) while auto-scroll had to wait —
    /// for the next page, or for a sheet over the player to close.
    func continueAutoScrollIfWaiting() {
        guard vm.videoEnded,
            ShortsEndOfVideoDecision.advancesAfterWaiting(
                settings: store.settings, failed: vm.playerError?.isFatal == true),
            currentIndex + 1 < videos.count, !isTransitioning, !isOverlayPresented
        else { return }
        performVerticalTransition(direction: -1) { goTo(currentIndex + 1) }
    }
    #endif

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

        // On iOS the target Short is normally already preloaded in its own pool slot
        // and sitting on its first frame, so this just starts it (see ShortsPlayerPool).
        currentIndex = index
        loadVideo(at: index)

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
    }

    #if os(iOS)
    /// The Shorts to keep preloaded around `index`: next first (the usual swipe), then
    /// previous.
    func neighbours(of index: Int) -> [Video] {
        [index + 1, index - 1].compactMap { videos.indices.contains($0) ? videos[$0] : nil }
    }

    /// The feed changed around the live Short (more Shorts arrived, a hidden channel
    /// was dropped): preload its current neighbours.
    func preloadNeighbours() {
        guard currentVideo != nil else { return }
        pool.preload(neighbours: neighbours(of: currentIndex), settings: store.settings)
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
        pool.show(live: video, neighbours: neighbours(of: index), settings: store.settings)
        pool.updateChannelId(video.channelId, for: video.id)
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
        case .advance where isOverlayPresented:
            // A sheet's actions target the current Short: loop it until the sheet closes.
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
            if isOverlayPresented {
                // Skipped once the sheet closes (`continueAutoScrollIfWaiting()`).
                vm.videoEnded = true
            } else if let next = ShortsNavigation.targetIndex(
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
