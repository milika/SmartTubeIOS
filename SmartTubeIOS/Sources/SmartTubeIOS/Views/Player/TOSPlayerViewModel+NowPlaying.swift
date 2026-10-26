#if os(iOS)
import UIKit
import MediaPlayer
import SmartTubeIOSCore

private let tosNowPlayingLog = CrashlyticsLogger(category: "TOSPlayer")

// File-scope factory — deliberately nonisolated so MPMediaItemArtwork can invoke the
// returned closure from MediaPlayer's internal serial queue without triggering the
// Swift 6 actor-isolation assertion. Mirrors PlaybackViewModel+NowPlaying.swift's
// identical helper — see that file's doc comment for the full story.
private func makeNonisolatedArtworkProvider(image: UIImage) -> (CGSize) -> UIImage {
    { _ in image }
}

// MARK: - Now Playing (lock screen + Dynamic Island + headphone controls)
//
// #283: TOSPlayerViewModel previously had zero MPNowPlayingInfoCenter/
// MPRemoteCommandCenter integration — confirmed live on device that the lock
// screen widget showed stale info from a previous AVPlayer session, with
// non-functional controls. This gives TOS player correct metadata and working
// play/pause/skip/seek/next/previous while the app is foregrounded or
// minimized to TOSFloatingPlayerView. It does NOT add background audio or system
// PiP — both were investigated and found not feasible without a hybrid
// AVPlayer-handoff approach the user explicitly rejected (see task-283).

extension TOSPlayerViewModel {

    func setupRemoteCommandCenter() {
        tosNowPlayingLog.notice("[NowPlaying] setupRemoteCommandCenter() called")
        let center = MPRemoteCommandCenter.shared()
        // Remove any existing targets first so this is safe to call multiple times
        // (e.g. on every loadEmbed) without accumulating duplicate handlers —
        // mirrors PlaybackViewModel.setupRemoteCommandCenter().
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.playInline()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pauseInline()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let self else { return .success }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self.seekTo(self.currentTime + interval)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let self else { return .success }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self.seekTo(max(0, self.currentTime - interval))
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .success }
            self?.seekTo(position)
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
    }

    func updateNowPlayingInfo() {
        tosNowPlayingLog.notice(
            "[NowPlaying] updateNowPlayingInfo — title='\(videoTitle)' channel='\(channelTitle)' duration=\(String(format: "%.1f", duration))s"
        )
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: videoTitle,
            MPMediaItemPropertyArtist: channelTitle,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.video.rawValue),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: currentTime),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: playerState == .playing ? 1.0 : 0.0),
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        nowPlayingInfoCache = info

        // Artwork — capture the current image by value so the MPMediaItemArtwork
        // closure never captures self (see makeNonisolatedArtworkProvider's doc
        // comment / PlaybackViewModel+NowPlaying.swift's fix238 for why).
        if let thumbnailURL {
            let snapshot: UIImage = cachedArtwork ?? UIImage()
            let artwork = MPMediaItemArtwork(
                boundsSize: CGSize(width: 600, height: 600),
                requestHandler: makeNonisolatedArtworkProvider(image: snapshot))
            nowPlayingInfoCache[MPMediaItemPropertyArtwork] = artwork

            if cachedArtworkVideoID != videoId {
                cachedArtworkVideoID = videoId
                cachedArtwork = nil
                Task { [weak self, url = thumbnailURL, videoID = videoId] in
                    guard let (data, _) = try? await URLSession.shared.data(from: url),
                        let image = UIImage(data: data)
                    else { return }
                    await MainActor.run { [weak self] in
                        guard let self, self.cachedArtworkVideoID == videoID else { return }
                        self.cachedArtwork = image
                        self.nowPlayingInfoCache[MPMediaItemPropertyArtwork] =
                            MPMediaItemArtwork(
                                boundsSize: image.size,
                                requestHandler: makeNonisolatedArtworkProvider(image: image))
                        self.setNowPlayingInfo(self.nowPlayingInfoCache)
                    }
                }
            }
        }

        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = hasPrevious

        setNowPlayingInfo(nowPlayingInfoCache)
    }

    func updateNowPlayingPlayback() {
        nowPlayingInfoCache[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: currentTime)
        nowPlayingInfoCache[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: playerState == .playing ? 1.0 : 0.0)
        setNowPlayingInfo(nowPlayingInfoCache)
    }

    func clearNowPlayingInfo() {
        cachedArtwork = nil
        cachedArtworkVideoID = nil
        nowPlayingInfoCache = [:]
        setNowPlayingInfo(nil)
    }

    /// Writes to `MPNowPlayingInfoCenter` directly on `@MainActor` (main thread).
    /// Do NOT dispatch async here — see PlaybackViewModel+NowPlaying.swift's
    /// identical doc comment for why that causes an EXC_BREAKPOINT.
    private func setNowPlayingInfo(_ info: [String: Any]?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
#endif
