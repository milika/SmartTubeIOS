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

    @Test("loadShort resets observable state for the new video")
    func loadShortResetsObservableState() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.playerState = .playing
        vm.currentTime = 42
        vm.duration = 60
        vm.isReady = true

        vm.loadShort(video: Video(id: "abc123", title: "Test Short", channelTitle: "Channel"))

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
        vm.loadShort(video: Video(id: "abc123", title: "Test Short", channelTitle: "Channel"))
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

    // MARK: - Standby pre-warm (#271)

    @Test("isStandby is false on fresh VM")
    func standbyFalseOnInit() {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.isStandby == false)
    }

    @Test("loadShortAsStandby sets isStandby = true before awaiting isReady")
    func standbyFlagSetByLoadShortAsStandby() async {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        #expect(vm.isStandby == false)
        let video = Video(id: "dQw4w9WgXcQ", title: "Test", channelTitle: "Channel")
        // loadShortAsStandby sets isStandby = true synchronously, then awaits isReady.
        // Cancel the task quickly — we only need to verify the flag is set.
        let task = Task { await vm.loadShortAsStandby(video: video) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await task.value
        #expect(vm.isStandby == true)
    }

    @Test("activate clears isStandby and does not crash on fresh VM")
    func activateClearsStandbyFlag() async {
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        let video = Video(id: "dQw4w9WgXcQ", title: "Test", channelTitle: "Channel")
        // Put the VM into standby state by starting (then cancelling) loadShortAsStandby.
        let task = Task { await vm.loadShortAsStandby(video: video) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await task.value
        #expect(vm.isStandby == true)
        vm.activate()
        #expect(vm.isStandby == false)
    }

    @Test("activate resets hasReceivedFirstTick so tickstarted can refire on re-promotion")
    func activateResetsHasReceivedFirstTick() {
        // Backward-swap (#277) reuses an ALREADY-ticked VM instance (previousVM),
        // unlike the forward standby path which always promotes a fresh VM (where
        // this flag is already false). Without resetting it here, the
        // "tickstarted" Darwin notification would never refire after a backward
        // swipe, since the gate in the WebBridge's "tick" handler is one-shot.
        let vm = ShortsEmbedPlayerViewModel(api: InnerTubeAPI())
        vm.hasReceivedFirstTick = true
        vm.activate()
        #expect(vm.hasReceivedFirstTick == false)
    }
}
#endif
