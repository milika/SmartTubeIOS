#if !os(tvOS)
import Foundation
import Testing
import SmartTubeIOSCore
@testable import SmartTubeIOS

@MainActor
@Suite("ShortsEmbedPlayerViewModel")
struct ShortsEmbedPlayerViewModelTests {

    @Test("Initial state before any loadShort() call")
    func initialState() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.playerState == .unstarted)
        #expect(vm.currentTime == 0)
        #expect(vm.duration == 0)
        #expect(vm.isReady == false)
        #expect(vm.playerError == nil)
        #expect(vm.sponsorSegments.isEmpty)
        #expect(vm.currentToastSegment == nil)
        #expect(vm.sleepTimerMinutes == nil)
        #expect(vm.videoId == "")
    }

    @Test("updateSettings stores the new settings")
    func updateSettingsStoresNewSettings() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        var settings = AppSettings()
        settings.loopEnabled = true
        vm.updateSettings(settings)
        #expect(vm.settings.loopEnabled == true)
    }

    @Test("syncSettings drops the loaded segments only when SponsorBlock settings change")
    func syncSettingsReloadsSegmentsOnSponsorBlockChange() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        let segment = SponsorSegment(start: 5, end: 10, category: .sponsor)
        vm.sponsorSegments = [segment]

        var settings = vm.settings
        settings.loopEnabled.toggle()
        vm.syncSettings(settings)
        #expect(vm.sponsorSegments == [segment])

        settings.shortsSponsorBlock = false
        vm.syncSettings(settings)
        #expect(vm.sponsorSegments.isEmpty)
        #expect(vm.settings.shortsSponsorBlock == false)
    }

    @Test("updateChannelId applies a channel exclusion to the loaded Short")
    func updateChannelIdAppliesExclusion() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        var settings = AppSettings()
        settings.sponsorBlockExcludedChannels = ["UCX": "Excluded"]
        vm.updateSettings(settings)
        vm.loadShort(video: Video(id: "a", title: "", channelTitle: "", isShort: true), live: true)
        vm.sponsorSegments = [SponsorSegment(start: 5, end: 10, category: .sponsor)]

        vm.updateChannelId("UCX", for: "other")  // stale: metadata for another Short
        #expect(vm.channelId == nil)
        #expect(vm.sponsorSegments.count == 1)

        vm.updateChannelId("UCX", for: "a")
        #expect(vm.channelId == "UCX")
        #expect(vm.sponsorSegments.isEmpty)
    }

    @Test("loadShort resets observable state for the new video")
    func loadShortResetsObservableState() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.playerState = .playing
        vm.currentTime = 42
        vm.duration = 60
        vm.isReady = true

        vm.loadShort(video: Video(id: "abc123", title: "Test Short", channelTitle: "Channel"), live: true)

        #expect(vm.videoId == "abc123")
        #expect(vm.playerState == .unstarted)
        #expect(vm.currentTime == 0)
        #expect(vm.duration == 0)
        #expect(vm.isReady == false)
    }

    @Test("checkSponsorSkip with no loaded segments does nothing")
    func checkSponsorSkipNoSegments() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.duration = 60

        vm.checkSponsorSkip(at: 5)

        #expect(vm.currentToastSegment == nil)
        #expect(vm.activeSkipEnd == nil)
        #expect(vm.pendingSkipLog == nil)
    }

    @Test("checkSponsorSkip auto-skips a sponsor segment and records a pending skip log")
    func checkSponsorSkipAutoSkipsSponsorSegment() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.duration = 60
        vm.sponsorSegments = [SponsorSegment(start: 5, end: 10, category: .sponsor)]

        vm.checkSponsorSkip(at: 6)

        #expect(vm.activeSkipEnd == 10)
        #expect(vm.currentToastSegment == nil)
        #expect(vm.pendingSkipLog?.category == .sponsor)
        #expect(vm.pendingSkipLog?.targetTime == 10)
    }

    @Test("checkSponsorSkip shows a toast for an intro segment instead of skipping")
    func checkSponsorSkipShowsToastForIntroSegment() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.duration = 60
        vm.sponsorSegments = [SponsorSegment(start: 5, end: 10, category: .intro)]

        vm.checkSponsorSkip(at: 6)

        #expect(vm.currentToastSegment?.category == .intro)
        #expect(vm.activeSkipEnd == nil)
        #expect(vm.pendingSkipLog == nil)
    }

    @Test("logSkipLanding clears the pending log once the seek lands")
    func logSkipLandingClearsPendingLogOnLanding() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.pendingSkipLog = PendingSkipLog(
            category: .sponsor, segmentStart: 5, segmentEnd: 10, beforeTime: 6, targetTime: 10
        )

        vm.logSkipLanding(at: 10)

        #expect(vm.pendingSkipLog == nil)
    }

    @Test("logSkipLanding times out after 16 ticks without landing")
    func logSkipLandingTimesOutWithoutLanding() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.pendingSkipLog = PendingSkipLog(
            category: .sponsor, segmentStart: 5, segmentEnd: 10, beforeTime: 6, targetTime: 10
        )

        for _ in 0..<16 {
            vm.logSkipLanding(at: 6)
            #expect(vm.pendingSkipLog != nil)
        }
        vm.logSkipLanding(at: 6)

        #expect(vm.pendingSkipLog == nil)
    }

    @Test("isPlaying reflects playerState")
    func isPlayingReflectsPlayerState() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.isPlaying == false)  // .unstarted
        vm.playerState = .playing
        #expect(vm.isPlaying == true)
        vm.playerState = .buffering
        #expect(vm.isPlaying == true)
        vm.playerState = .paused
        #expect(vm.isPlaying == false)
    }

    @Test("currentVideoId tracks videoId after loadShort")
    func currentVideoIdTracksVideoId() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.currentVideoId == "")
        vm.loadShort(video: Video(id: "abc123", title: "Test Short", channelTitle: "Channel"), live: true)
        #expect(vm.currentVideoId == "abc123")
        #expect(vm.currentVideoId == vm.videoId)
    }

    @Test("showControls and toggleControls update controlsVisible")
    func showControlsAndToggleControls() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.controlsVisible == false)
        vm.showControls()
        #expect(vm.controlsVisible == true)
        vm.toggleControls()
        #expect(vm.controlsVisible == false)
        vm.toggleControls()
        #expect(vm.controlsVisible == true)
        vm.cancelControlsHide()
        #expect(vm.controlsVisible == true)
    }

    @Test("resume does not show controls — controls stay hidden on initial load")
    func resumeDoesNotShowControls() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.wasPlayingBeforeSuspend = true
        #expect(vm.controlsVisible == false)
        vm.resume()
        #expect(vm.controlsVisible == false)
        #expect(vm.wasPlayingBeforeSuspend == false)
    }

    @Test("handleBackground pauses and sets wasPlayingBeforeSuspend; handleForeground resumes")
    func handleBackgroundAndForeground() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.playerState = .playing
        vm.handleBackground()
        #expect(vm.wasPlayingBeforeSuspend == true)
        vm.handleForeground()
        #expect(vm.wasPlayingBeforeSuspend == false)
    }

    @Test("handleBackground does nothing when not playing")
    func handleBackgroundNoOpWhenNotPlaying() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.playerState == .unstarted)
        vm.handleBackground()
        #expect(vm.wasPlayingBeforeSuspend == false)
    }

    @Test("errorMessage maps each TOSPlayerError case to a non-empty string")
    func errorMessageMapsErrorCases() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.errorMessage == nil)
        vm.playerError = .notFound
        #expect(vm.errorMessage?.isEmpty == false)
        vm.playerError = .embeddingDisabled
        #expect(vm.errorMessage?.isEmpty == false)
        vm.playerError = .iframeError(153)
        #expect(vm.errorMessage?.isEmpty == false)
        vm.playerError = .webViewLoadFailed
        #expect(vm.errorMessage?.isEmpty == false)
        vm.playerError = .signInRequired
        #expect(vm.errorMessage?.isEmpty == false)
    }

    @Test("togglePlayPause replays from start when the video has ended")
    func togglePlayPauseReplaysWhenVideoEnded() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.videoEnded = true
        vm.togglePlayPause()
        #expect(vm.videoEnded == false)
    }

    // MARK: - TOSPlayerError.isFatal (regression guard for Firebase issue 8c362d98 / task #270)
    //
    // ShortsPlayerView.onChange(of: vm.playerError) calls advanceAfterError() only when
    // error.isFatal is true. These tests lock in which error codes auto-advance Shorts.

    @Test("iframeError(153) is fatal — triggers Shorts auto-advance (non-embeddable video)")
    func iframeError153IsFatal() {
        #expect(TOSPlayerError.iframeError(153).isFatal == true)
    }

    @Test("webViewLoadFailed is fatal — ready-timeout path also auto-advances")
    func webViewLoadFailedIsFatal() {
        #expect(TOSPlayerError.webViewLoadFailed.isFatal == true)
    }

    @Test("embeddingDisabled is fatal")
    func embeddingDisabledIsFatal() {
        #expect(TOSPlayerError.embeddingDisabled.isFatal == true)
    }

    @Test("notFound is fatal")
    func notFoundIsFatal() {
        #expect(TOSPlayerError.notFound.isFatal == true)
    }

    @Test("iframeError with non-fatal codes does not auto-advance")
    func iframeErrorNonFatalCodesAreNotFatal() {
        #expect(TOSPlayerError.iframeError(2).isFatal == false)
        #expect(TOSPlayerError.iframeError(5).isFatal == false)
        #expect(TOSPlayerError.iframeError(999).isFatal == false)
    }

    // MARK: - Live / held (ShortsPlayerPool)

    private func short(_ id: String) -> Video {
        Video(id: id, title: "Test", channelTitle: "Channel", isShort: true)
    }

    @Test("A fresh VM is not live")
    func freshVMIsNotLive() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.isLive == false)
        #expect(vm.hasFrame == false)
        #expect(vm.video == nil)
    }

    @Test("loadShort(live:) sets the mode and resets hasFrame")
    func loadShortSetsMode() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: false)
        #expect(vm.isLive == false)
        #expect(vm.logTag.hasSuffix("/held"))
        vm.hasFrame = true

        vm.loadShort(video: short("b"), live: true)
        #expect(vm.isLive == true)
        #expect(vm.hasFrame == false)
        #expect(vm.video?.id == "b")
    }

    @Test("activate makes a held Short live without reloading it")
    func activateKeepsPreloadedShort() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: false)
        vm.isReady = true
        vm.hasFrame = true
        vm.playerState = .paused
        vm.hasReceivedFirstTick = true

        vm.activate()

        #expect(vm.isLive == true)
        #expect(vm.isReady == true)
        #expect(vm.hasFrame == true)
        #expect(vm.hasReceivedFirstTick == false)
        // The held embed reported "paused"; the paused icon must not flash.
        #expect(vm.playerState == .buffering)
    }

    @Test("activate is a no-op for the live Short")
    func activateNoOpWhenLive() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: true)
        vm.hasReceivedFirstTick = true
        vm.playerState = .paused

        vm.activate()

        #expect(vm.hasReceivedFirstTick == true)
        #expect(vm.playerState == .paused)
    }

    @Test("activate reloads a held Short whose preload timed out")
    func activateRetriesTimedOutPreload() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: false)
        vm.playerError = .webViewLoadFailed

        vm.activate()

        #expect(vm.isLive == true)
        #expect(vm.playerError == nil)
        #expect(vm.videoId == "a")
    }

    @Test("activate keeps a held Short's fatal embed error so the player skips it")
    func activateKeepsEmbedError() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: false)
        vm.playerError = .embeddingDisabled

        vm.activate()

        #expect(vm.isLive == true)
        #expect(vm.playerError == .embeddingDisabled)
    }

    @Test("deactivate puts the live Short back on hold")
    func deactivateReturnsToHeld() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.loadShort(video: short("a"), live: true)
        vm.videoEnded = true
        vm.showControls()

        vm.deactivate()

        #expect(vm.isLive == false)
        #expect(vm.videoEnded == false)
        #expect(vm.controlsVisible == false)
        #expect(vm.videoId == "a")
    }
}

#if os(iOS)
@MainActor
@Suite("ShortsPlayerPool")
struct ShortsPlayerPoolTests {

    private func short(_ id: String) -> Video {
        Video(id: id, title: "Test", channelTitle: "Channel", isShort: true)
    }

    @Test("show plays the live Short and preloads its neighbours held")
    func showPreloadsNeighbours() {
        let pool = ShortsPlayerPool(api: InnerTubeAPI())
        pool.show(live: short("a"), neighbours: [short("b")], settings: AppSettings())

        #expect(pool.live.video?.id == "a")
        #expect(pool.live.isLive)
        let next = pool.player(holding: "b")
        #expect(next != nil)
        #expect(next?.isLive == false)
        #expect(pool.players.filter(\.isLive).count == 1)
    }

    @Test("Swiping onto a preloaded Short reuses its player instead of reloading")
    func swipeReusesPreloadedPlayer() {
        let pool = ShortsPlayerPool(api: InnerTubeAPI())
        pool.show(live: short("a"), neighbours: [short("b")], settings: AppSettings())
        let previous = pool.live
        let next = pool.player(holding: "b")
        next?.isReady = true
        next?.hasFrame = true

        pool.show(live: short("b"), neighbours: [short("c"), short("a")], settings: AppSettings())

        #expect(pool.live === next)
        #expect(pool.live.isLive)
        #expect(pool.live.isReady)  // not reloaded
        #expect(pool.live.hasFrame)
        #expect(previous.isLive == false)
        #expect(pool.player(holding: "a") === previous)
        #expect(pool.player(holding: "c")?.isLive == false)
        #expect(pool.players.filter(\.isLive).count == 1)
    }

    @Test("preload never changes the live Short")
    func preloadLeavesLiveAlone() {
        let pool = ShortsPlayerPool(api: InnerTubeAPI())
        pool.show(live: short("a"), neighbours: [], settings: AppSettings())
        let live = pool.live

        pool.preload(neighbours: [short("b")], settings: AppSettings())

        #expect(pool.live === live)
        #expect(pool.live.isLive)
        #expect(pool.player(holding: "b")?.isLive == false)
    }
}
#endif
#endif
