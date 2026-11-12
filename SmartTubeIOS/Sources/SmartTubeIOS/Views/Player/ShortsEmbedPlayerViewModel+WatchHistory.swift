#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

// MARK: - Watch History / Mark-as-Watched
//
// Adapts TOSPlayerViewModel+WatchHistory.swift's WatchtimeTracker integration for a
// view model that plays many Shorts in sequence (one persistent instance per Shorts
// session, vs. one TOSPlayerViewModel instance per video). TOS calls
// tracker.transition(...) ONCE, from "ready" — opening the session for its single
// video with a no-op flush (no prior video in that instance's lifetime). Here,
// transitionWatchHistory(to:) is called from EVERY loadShort(video:) (see Task 7,
// Step 3): each swipe both flushes the OUTGOING Short's watch interval
// ([0, currentTime], via tracker.transition's returned closure) and opens a fresh
// session for the incoming Short. The very first call behaves like TOS's: the
// tracker's internal videoId is empty, so the flush closure no-ops.

extension ShortsEmbedPlayerViewModel {

    /// Flushes the outgoing Short's watch-progress report and opens a WatchtimeTracker
    /// session for `newVideoId`. Must be called BEFORE `loadShort(video:)` resets
    /// `currentTime`/`duration`/`videoId` to the new Short's (zeroed) values — see
    /// Task 7, Step 3.
    func transitionWatchHistory(to newVideoId: String) {
        guard settings.historyState == .enabled else {
            shortsLog.debug("[watchtime] history disabled — skipping tracker transition")
            return
        }
        let outgoingVideoId = videoId
        let flush = tracker.transition(
            to: newVideoId, cpn: InnerTubeAPI.generateCPN(),
            flushPosition: currentTime, flushDuration: duration
        )
        Task { await flush() }
        shortsLog.notice("[watchtime] session transitioned \(outgoingVideoId) → \(newVideoId)")
        // The tracker resolves the account-bound tracking URLs on the first checkpoint.
    }

    /// Checkpoints the last-displayed Short's watch position/duration when the Shorts
    /// player session ends. Identical to
    /// TOSPlayerViewModel+WatchHistory.swift's saveProgress() — called from
    /// `ShortsPlayerView.onDisappear` (Task 9).
    func saveProgress() {
        guard settings.historyState == .enabled, duration > 0 else {
            shortsLog.debug(
                "[watchtime] saveProgress skipped — historyState=\(self.settings.historyState.rawValue, privacy: .public) duration=\(self.duration, format: .fixed(precision: 1))s"
            )
            return
        }
        let pos = currentTime
        let dur = duration
        Task {
            await self.tracker.checkpoint(position: pos, duration: dur)
            shortsLog.notice("[watchtime] checkpoint saved — videoId=\(self.videoId) pos=\(Int(pos))s dur=\(Int(dur))s")
        }
    }
}
#endif  // !os(tvOS)
