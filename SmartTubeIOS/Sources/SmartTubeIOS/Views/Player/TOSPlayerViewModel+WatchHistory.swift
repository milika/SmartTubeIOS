#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let tosLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - Watch History / Position Checkpointing
//
// Parity fix: the standard PlaybackViewModel begins a WatchtimeTracker session via
// tracker.transition(...) from load(), resolves account-bound tracking URLs, and
// checkpoints the watch position from suspend()/stop() — both of which fire from
// the player view's onDisappear (see PlayerView+Lifecycle.swift). Before this change
// TOSPlayerViewModel did none of this: closing a TOS-played video silently lost the
// watch position (resume-from-last-position was a one-shot read at startup, never
// written back) and TOS sessions never appeared in "continue watching"/history.
//
// Lifecycle here (simpler than the standard player's, since each TOSPlayerViewModel
// instance is scoped to exactly one video — there is no in-place video switch):
//   "ready"      → beginWatchtimeTracking(): tracker.transition(...) opens the
//                  session (the returned flush closure is a no-op — no prior video
//                  in this instance's lifetime), then resolves cached tracking URLs.
//   onDisappear  → saveProgress(): single checkpoint with the final position/duration,
//                  mirroring stop()'s "save on close" semantics.

extension TOSPlayerViewModel {

    func ensureTrackingSession() async {
        guard !tracker.hasTrackingSession else { return }
        if let task = trackingSessionTask {
            await task.value
            return
        }
        let videoId = videoId
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.trackingSessionTask = nil }
            do {
                let urls = await self.api.fetchHistoryTrackingURLs(videoId: videoId)
                self.tracker.setTrackingURLs(urls)
            } catch {
            }
        }
        trackingSessionTask = task
        await task.value
    }

    /// Opens a WatchtimeTracker session for this video once playback is ready (duration
    /// known) and resolves any cached account-bound tracking URLs. Mirrors the
    /// `tracker.transition(...)` + `tracker.setTrackingURLs(...)` calls in
    /// `PlaybackViewModel+Loading.swift`'s load()/prefetch path, collapsed into one
    /// step since this view model never switches videos in place.
    func beginWatchtimeTracking() {
        guard !isIncognito else {
            tosLog.debug("[watchtime] incognito — skipping tracker session for \(self.videoId)")
            return
        }
        guard settings.historyState == .enabled else {
            tosLog.debug("[watchtime] history disabled — skipping tracker session")
            return
        }
        // #150: on-device history (the YouTube account can't be written to — see
        // LocalWatchHistoryStore). Guards above already cover Incognito / history disabled.
        LocalWatchHistoryStore.shared.record(
            Video(
                id: videoId, title: videoTitle, channelTitle: channelTitle, channelId: channelId,
                thumbnailURL: thumbnailURL))
        // No prior session in this instance's lifetime — flushPosition/flushDuration
        // of 0 means the returned flush closure is a guaranteed no-op (oldVideoId is
        // empty), exactly like the very first transition() call in a fresh
        // PlaybackViewModel. We still go through transition() (rather than hand-rolling
        // session state) so cpn/videoId bookkeeping stays identical to the standard path.
        let flush = tracker.transition(
            to: videoId, cpn: InnerTubeAPI.generateCPN(),
            flushPosition: 0, flushDuration: 0)
        Task { await flush() }
        tosLog.notice("[watchtime] session opened for \(self.videoId)")

        // Deliberately NOT [weak self]: unlike the SponsorBlock background-revalidation
        // task above (whose result only matters if the player is still on screen), this
        // result feeds the checkpoint that fires on dismissal — it must survive even if
        // `self` would otherwise be released the instant the view disappears. Capturing
        // `self` strongly here simply keeps the view model alive until this short
        // in-memory cache lookup resolves; it cannot create a retain cycle (Task does
        // not hold a strong reference back to its creator).
        //
        // Single consume() also seeds `likeStatus` from any cached `nextInfo` — mirrors
        // `if let status = nextInfo?.likeStatus { likeStatus = status }` in
        // PlaybackViewModel+Loading. Cache-only (no live nextInfo fetch): a miss simply
        // leaves likeStatus at .none, which is still functionally correct — like()/
        // dislike() optimistic-update from whatever the current value is and roll back
        // on failure, so a stale "not liked" display just means the first tap reflects
        // the true state once the API call lands. A live fetch here would mean pulling
        // in the standard player's much larger nextInfo/related-videos prefetch chain
        // for a cosmetic-only initial-state nicety — out of proportion to this transfer.
        let videoId = videoId
        Task {
            let cached = await VideoPreloadCache.shared.consume(videoId: videoId)
            // Outer nil = not cached (treat as "no URLs yet"); inner nil = cached "no URLs".
            // `?? nil` flattens PlaybackTrackingURLs?? → PlaybackTrackingURLs? either way.
            let cachedURLs = cached.trackingURLs ?? nil
            let urls: PlaybackTrackingURLs?
            if let cachedURLs {
                urls = cachedURLs
            } else {
                urls = await api.fetchHistoryTrackingURLs(videoId: videoId)
            }
            self.tracker.setTrackingURLs(urls)
            if let status = cached.nextInfo?.likeStatus {
                self.likeDislike.setLikeStatus(status)
                tosLog.notice(
                    "[likeDislike] seeded likeStatus=\(String(describing: status), privacy: .public) from cached nextInfo"
                )
            }
        }
    }

    /// Throttled watch-history checkpoint driven by the player's tick, so progress
    /// survives a crash or app kill instead of only being written on dismiss.
    func checkpointIfDue() {
        guard !isIncognito, settings.historyState == .enabled, duration > 0 else { return }
        let pos = currentTime
        let dur = duration
        Task {
            await self.ensureTrackingSession()
            await self.tracker.checkpointIfDue(position: pos, duration: dur)
        }
    }

    func recordSeek(to target: Double, from position: Double) {
        guard !isIncognito, settings.historyState == .enabled, duration > 0 else { return }
        let dur = duration
        Task {
            await self.ensureTrackingSession()
            await self.tracker.recordSeek(to: target, from: position, duration: dur)
        }
    }

    /// Checkpoints the final watch position/duration when the player view disappears
    /// (close button, Esc key, or fallback transition — see TOSPlayerView.onDisappear).
    /// Mirrors `stop()`'s "save position on close" semantics in PlaybackViewModel —
    /// this is the write-back half that was previously entirely missing: TOS playback
    /// only ever *read* a saved position once at startup (TOSPlayerView.task) and never
    /// wrote one back, so progress was lost on every close.
    func saveProgress() {
        guard !isIncognito, settings.historyState == .enabled, duration > 0 else {
            return
        }
        let pos = currentTime
        let dur = duration
        // Strong capture is intentional and required: this fires from onDisappear,
        // at which point SwiftUI may release `vm` (and thus `self`) at any moment.
        // [weak self] here would make the entire feature a no-op — exactly the bug
        // we're fixing, just moved one layer down. Mirrors PlaybackViewModel.stop()'s
        // `Task { await self.tracker.checkpoint(...) }` (also a strong capture, for
        // the same reason: the checkpoint must outlive the call site).
        Task {
            await self.ensureTrackingSession()
            await self.tracker.checkpoint(position: pos, duration: dur)
        }
    }
}
#endif  // !os(tvOS)
