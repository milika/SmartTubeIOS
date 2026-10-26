#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let tosLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - Navigation (swipe left/right)
//
// Backs TOSSwipeNavigationOverlay. `relatedVideos` is populated from the "ready"
// bridge message (see TOSPlayerViewModel+WebBridge.swift) using the same
// cache-first/stale-revalidate/full-miss pattern as fetchSponsorSegments()
// (TOSPlayerViewModel+SponsorBlock.swift).
//
// Navigation priority:
//   1. CurrentQueue playlist  — playlistId == CurrentQueueStore.playlistID
//      Swipe-left  → next queue item (wraps to index 0 at end)
//      Swipe-right → previous queue item (wraps to last at start)
//   2. Suggestions (relatedVideos) — all other cases
//      seenVideoIds filters already-watched videos to avoid loop-back.

extension TOSPlayerViewModel {
    /// Whether a "next" suggestion video is available to swipe to.
    /// Always true for CurrentQueue (wraps around), true for suggestions when non-empty.
    var hasNext: Bool {
        if playlistId == CurrentQueueStore.playlistID { return true }
        return !relatedVideos.isEmpty
    }

    /// True when this video was opened from the Current Queue — i.e. a YouTube
    /// playlist, search "play all", or the Library queue. Only those videos get
    /// the synthetic queue `playlistId` (`CurrentQueueStore.videoAt(index:)`).
    var isInPlaylist: Bool {
        playlistId == CurrentQueueStore.playlistID
    }

    /// Enables the "previous video" transport button. Playlist-only: a
    /// non-playlist video (suggestions are reachable via swipe) or a one-item
    /// queue keeps it disabled.
    var canPlayPreviousVideo: Bool {
        TOSPlayerTransportSupport.canNavigatePlaylist(
            playlistId: playlistId,
            queuePlaylistID: CurrentQueueStore.playlistID,
            queueCount: playlistVideoCount
        )
    }

    /// Enables the "next video" transport button. See `canPlayPreviousVideo`.
    var canPlayNextVideo: Bool {
        TOSPlayerTransportSupport.canNavigatePlaylist(
            playlistId: playlistId,
            queuePlaylistID: CurrentQueueStore.playlistID,
            queueCount: playlistVideoCount
        )
    }

    /// Re-reads the Current Queue length so the playlist buttons reflect the
    /// live queue (it can change while a video is playing). No-op when the
    /// video is not part of the queue.
    func refreshPlaylistVideoCount() async {
        guard isInPlaylist else {
            playlistVideoCount = 0
            return
        }
        playlistVideoCount = await CurrentQueueStore.shared.videos.count
    }

    /// Called by `TOSPlayerStateStore.play(video:api:)` after creating this vm.
    func setNavigationContext(hasPrevious: Bool) {
        self.hasPrevious = hasPrevious
    }

    /// Swipe-left handler.
    /// - CurrentQueue: advance to the next queue item, wrapping to index 0 at end.
    /// - Suggestions: play the first related video.
    func playNext() {
        if playlistId == CurrentQueueStore.playlistID, let idx = playlistIndex {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let count = await CurrentQueueStore.shared.videos.count
                guard count > 0 else { return }
                let nextIdx = (idx + 1) % count
                guard let next = await CurrentQueueStore.shared.videoAt(index: nextIdx) else { return }
                tosLog.notice(
                    "[navigation] playNext (queue) — index=\(nextIdx)/\(count) id=\(next.id, privacy: .public)")
                onPlayNext?(next)
            }
            return
        }
        tosLog.notice(
            "[navigation] playNext called — relatedVideos=\(self.relatedVideos.count) hasNext=\(self.hasNext)")
        guard let next = relatedVideos.first else { return }
        tosLog.notice("[navigation] playNext — \(next.id, privacy: .public)")
        onPlayNext?(next)
    }

    /// Called when the embed reports `playerState == .ended`. Mirrors
    /// PlaybackViewModel+Navigation.handlePlaybackEnd()'s gating exactly:
    /// loop takes priority, then queue/playlist continuation happens
    /// unconditionally (matches the AVPlayer pipeline — playlist intent implies
    /// sequential playback regardless of the general Autoplay toggle), and only
    /// the final "suggestions" fallback is gated by `settings.autoplayEnabled`.
    /// `playNext()` already contains the queue-vs-suggestions logic, so this only
    /// needs to add the gating `handlePlaybackEnd()` itself doesn't have.
    func handlePlaybackEnd() {
        if settings.loopEnabled {
            tosLog.notice("[navigation] handlePlaybackEnd — loop enabled, replaying")
            seekTo(0)
            play()
            return
        }
        if playlistId == CurrentQueueStore.playlistID {
            tosLog.notice("[navigation] handlePlaybackEnd — queue context, advancing unconditionally")
            playNext()
            return
        }
        guard settings.autoplayEnabled else {
            tosLog.notice("[navigation] handlePlaybackEnd — autoplay disabled, leaving native end screen")
            return
        }
        tosLog.notice("[navigation] handlePlaybackEnd — autoplay enabled, advancing to suggestion")
        playNext()
    }

    /// Swipe-right handler.
    /// - CurrentQueue: go to the previous queue item, wrapping to last at start.
    /// - Suggestions: re-play the most recent history entry.
    func playPrevious() {
        if playlistId == CurrentQueueStore.playlistID, let idx = playlistIndex {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let count = await CurrentQueueStore.shared.videos.count
                guard count > 0 else { return }
                let prevIdx = idx > 0 ? idx - 1 : count - 1
                guard let prev = await CurrentQueueStore.shared.videoAt(index: prevIdx) else { return }
                tosLog.notice(
                    "[navigation] playPrevious (queue) — index=\(prevIdx)/\(count) id=\(prev.id, privacy: .public)")
                onPlayNext?(prev)
            }
            return
        }
        tosLog.notice("[navigation] playPrevious called — hasPrevious=\(self.hasPrevious)")
        guard hasPrevious else { return }
        tosLog.notice("[navigation] playPrevious — navigating back")
        onPlayPrevious?()
    }

    /// Cache-first fetch of related videos for swipe-left navigation.
    /// Mirrors PlaybackViewModel+Loading.swift's related-video fetch with the
    /// same search fallback when fetchNextInfo returns 0 results.
    /// Results are filtered against `seenVideoIds` to prevent loop-back.
    func fetchRelatedVideos() async {
        let videoId = videoId
        let cached = await VideoPreloadCache.shared.consume(videoId: videoId)
        if let cachedNextInfo = cached.nextInfo {
            let isStale = cached.staleFields.contains(.nextInfo)
            relatedVideos = filter(cachedNextInfo.relatedVideos, videoId: videoId)
            chapters = cachedNextInfo.chapters
            tosLog.notice(
                "[navigation] cache \(isStale ? "STALE" : "HIT") — \(self.relatedVideos.count) related video(s), \(self.chapters.count) chapter(s) for \(videoId)"
            )
            if relatedVideos.isEmpty { await searchFallback() }
            guard isStale else { return }
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                guard let fresh = try? await self.api.fetchNextInfo(videoId: videoId) else { return }
                await VideoPreloadCache.shared.store(nextInfo: fresh, for: videoId)
                await MainActor.run {
                    let updated = self.filter(fresh.relatedVideos, videoId: videoId)
                    tosLog.notice("[navigation] revalidated — \(updated.count) related video(s) for \(videoId)")
                    if !updated.isEmpty { self.relatedVideos = updated }
                    self.chapters = fresh.chapters
                }
            }
            return
        }

        guard let fresh = try? await api.fetchNextInfo(videoId: videoId) else {
            tosLog.notice("[navigation] fetchNextInfo failed for \(videoId)")
            await searchFallback()
            return
        }
        await VideoPreloadCache.shared.store(nextInfo: fresh, for: videoId)
        relatedVideos = filter(fresh.relatedVideos, videoId: videoId)
        chapters = fresh.chapters
        tosLog.notice(
            "[navigation] cache MISS — fetched \(self.relatedVideos.count) related video(s), \(self.chapters.count) chapter(s) for \(videoId)"
        )
        if relatedVideos.isEmpty { await searchFallback() }
    }

    /// Search-based fallback when fetchNextInfo returns 0 related videos —
    /// mirrors PlaybackViewModel+Loading.swift:1267-1273.
    private func searchFallback() async {
        guard !videoTitle.isEmpty else { return }
        tosLog.notice("[navigation] search fallback — query='\(self.videoTitle, privacy: .public)'")
        guard let result = try? await api.search(query: videoTitle) else { return }
        let videos = filter(result.videos, videoId: videoId)
        guard !videos.isEmpty else { return }
        relatedVideos = Array(videos.prefix(25))
        tosLog.notice("[navigation] search fallback — \(self.relatedVideos.count) video(s)")
    }

    /// Removes the current video and any already-seen videos from a candidate list.
    private func filter(_ videos: [Video], videoId: String) -> [Video] {
        videos.filter { $0.id != videoId && !seenVideoIds.contains($0.id) }
    }
}
#endif  // !os(tvOS)
