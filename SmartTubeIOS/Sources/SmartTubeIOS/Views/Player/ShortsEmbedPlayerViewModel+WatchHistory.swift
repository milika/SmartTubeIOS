#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

// MARK: - Watch History / Mark-as-Watched
//
// Adapts TOSPlayerViewModel+WatchHistory.swift's WatchtimeTracker integration for a
// view model that plays many Shorts in sequence and also preloads Shorts nobody has
// watched yet (`ShortsPlayerPool`'s held neighbours). A watch session opens when a
// Short goes live (`beginWatchSession()`, from `loadShort(video:live:)` or
// `activate()`) and is flushed with the watched interval [0, currentTime] when it
// stops being live (`endWatchSession()`, from `deactivate()` or the next live load).
// Preloading alone never reports anything.

extension ShortsEmbedPlayerViewModel {

    /// Opens a WatchtimeTracker session for the current Short. Any earlier session of
    /// this VM was already flushed by `endWatchSession()`.
    func beginWatchSession() {
        guard settings.historyState == .enabled else {
            shortsLog.debug("[watchtime] history disabled — skipping tracker session")
            return
        }
        let newVideoId = videoId
        tracker.transition(to: newVideoId, cpn: InnerTubeAPI.generateCPN(), flushPosition: 0, flushDuration: 0)
        shortsLog.notice("[watchtime] session opened for \(newVideoId)")

        // Resolve cached account-bound tracking URLs for the new video — mirrors
        // TOSPlayerViewModel+WatchHistory.swift's beginWatchtimeTracking() cache
        // consume. A cache miss simply leaves trackingURLs nil (anonymous reporting),
        // which is still functionally correct.
        Task {
            let cached = await VideoPreloadCache.shared.consume(videoId: newVideoId)
            let urls = cached.trackingURLs ?? nil
            self.tracker.setTrackingURLs(urls)
            shortsLog.notice(
                "[watchtime] trackingURLs resolved for \(newVideoId): \(urls != nil ? "account-bound" : "none")")
        }
    }

    /// Flushes the live Short's watched interval and closes its session. Must run
    /// before `currentTime`/`duration` are reset for another Short.
    func endWatchSession() {
        guard settings.historyState == .enabled else { return }
        let flush = tracker.transition(
            to: "", cpn: InnerTubeAPI.generateCPN(),
            flushPosition: currentTime, flushDuration: duration
        )
        Task { await flush() }
        shortsLog.notice("[watchtime] session closed for \(self.videoId) at \(Int(self.currentTime))s")
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
