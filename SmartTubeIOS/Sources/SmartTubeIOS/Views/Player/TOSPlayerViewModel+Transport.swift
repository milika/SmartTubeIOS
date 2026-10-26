#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let transportLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - Native transport
//
// Inline play/pause + scrubbing for the TOS transport overlay. The JS player
// remains authoritative: these methods send one command and then read the
// resulting state from the next tick (or the immediate `seeked` poll).
extension TOSPlayerViewModel {

    /// True while the embedded player is actively playing or buffering.
    /// `buffering` is treated as playing so the button shows pause during a
    /// short stall, matching the direct player's `isPlaying` behaviour.
    var isPlaying: Bool {
        playerState == .playing || playerState == .buffering
    }

    /// The chapter containing the current playhead, if chapters are available.
    var currentChapter: Chapter? {
        chapters.last(where: { $0.startTime <= currentTime })
    }

    /// True when a chapter starts after the current playhead — enables the
    /// "next chapter" transport button.
    var hasNextChapter: Bool {
        TOSPlayerTransportSupport.nextChapterStart(in: chapters, after: currentTime) != nil
    }

    /// True when the playhead can move backward to a chapter boundary — either
    /// the start of the current chapter (>3 s in) or the previous one.
    var hasPreviousChapter: Bool {
        TOSPlayerTransportSupport.previousChapterStart(in: chapters, currentTime: currentTime) != nil
    }

    /// Seeks to the start of the next chapter (no-op at the last chapter).
    func skipToNextChapter() {
        guard let target = TOSPlayerTransportSupport.nextChapterStart(in: chapters, after: currentTime) else {
            return
        }
        transportLog.notice("[chapter] skip next → \(target, format: .fixed(precision: 1))s")
        seekTo(target)
    }

    /// Restarts the current chapter when >3 s into it, otherwise seeks to the
    /// start of the previous chapter (no-op at the first chapter).
    func skipToPreviousChapter() {
        guard
            let target = TOSPlayerTransportSupport.previousChapterStart(
                in: chapters, currentTime: currentTime)
        else { return }
        transportLog.notice("[chapter] skip previous → \(target, format: .fixed(precision: 1))s")
        seekTo(target)
    }

    // MARK: Play / pause

    func togglePlayPause() {
        if playerState == .ended {
            seekTo(0)
            playInline()
        } else if isPlaying {
            pauseInline()
        } else {
            playInline()
        }
    }

    /// Resumes playback without using `pauseAllMediaPlayback` (which is for
    /// dismissal, not a normal transport pause). A short verification pass
    /// recovers from WebKit's occasional "plays then re-pauses" race.
    func playInline() {
        playPauseEpoch &+= 1
        let epoch = playPauseEpoch
        eval(
            "play",
            "(function(){var v=document.querySelector('video');if(v){v.play();}return {found:!!v,paused:v?v.paused:null};})();"
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, self.playPauseEpoch == epoch else { return }
            self.eval(
                "verifyPlay",
                "(function(){var v=document.querySelector('video');if(v&&v.paused){v.play();}return {paused:v?v.paused:null};})();"
            )
        }
    }

    /// Inline pause. Deliberately does **not** call `pauseAllMediaPlayback`;
    /// that OS-level suspension remains reserved for dismissal/mini-player
    /// stop paths, where it must silence every frame.
    func pauseInline() {
        playPauseEpoch &+= 1
        eval(
            "pause",
            "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.pause();}return {found:!!v,iframes:ifr,paused:v?v.paused:null};})();"
        )
    }

    // MARK: Scrubbing

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        scrubTime = currentTime
        transportLog.debug("[scrub] begin at \(self.currentTime, format: .fixed(precision: 1))s")
    }

    func updateScrub(to time: Double) {
        guard isScrubbing else { return }
        scrubTime = TOSPlayerTransportSupport.clampedScrubTime(time, duration: duration)
    }

    func commitScrub() {
        guard isScrubbing else { return }
        let target = scrubTime
        isScrubbing = false
        pendingSeekTarget = target
        pendingSeekSetAt = .now
        transportLog.notice("[scrub] commit to \(target, format: .fixed(precision: 1))s")
        seekTo(target)
    }

    // MARK: Tick application

    /// Applies a tick's playhead only when the native UI is not scrubbing and
    /// the last committed seek has landed (or timed out). Everything else
    /// (duration, buffered/seekable ranges, live/ad flags) is applied by the
    /// caller regardless of the scrub window.
    func applyTickCurrentTime(_ time: Double) {
        guard !isScrubbing else { return }
        if let pending = pendingSeekTarget {
            let landed = abs(time - pending) < 0.75
            let timedOut = pendingSeekSetAt.map { Date.now.timeIntervalSince($0) > 2.0 } ?? true
            if landed || timedOut {
                pendingSeekTarget = nil
                pendingSeekSetAt = nil
            } else {
                return
            }
        }
        currentTime = time
        captionsManager.updateCaptionCue(for: time)
    }

    func updatePlaybackWindow(
        buffered: [ClosedRange<Double>],
        seekable: [ClosedRange<Double>],
        live: Bool,
        ad: Bool
    ) {
        bufferedRanges = buffered
        seekableRanges = seekable
        isLive = live
        isAd = ad
        // A live broadcast reports an Infinity duration in the embed; the tick's
        // duration is then 0. Derive the timeline length from the DVR seekable
        // window so the progress bar has a real scale (and scrubbing works).
        if live, duration <= 0, let liveEdge = seekable.last?.upperBound, liveEdge > 0 {
            duration = liveEdge
        }
    }

    /// Decodes the `[[start, end], ...]` arrays sent by `stateDetectionJS`.
    /// Kept as a thin instance wrapper so the tick handler reads naturally;
    /// the parsing itself lives in `TOSPlayerTransportSupport` for testing.
    func parseRanges(_ value: Any?) -> [ClosedRange<Double>] {
        TOSPlayerTransportSupport.parseRanges(value)
    }
}
#endif
