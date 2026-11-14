import AVFoundation
import SmartTubeIOSCore
import os

private let audioOnlyLog = CrashlyticsLogger(category: "AudioOnly")

// MARK: - Audio-Only Playback Mode

extension PlaybackViewModel {

    /// Toggles audio-only mode on the **currently playing video** immediately.
    /// - Turning ON: overlay appears immediately; attempts to swap to an audio-only
    ///   stream in the background. If the swap fails, the overlay stays visible with
    ///   HLS audio playing underneath — the setting is NOT reverted.
    /// - Turning OFF: overlay hides; reloads HLS only if an audio-only stream was
    ///   successfully loaded (tracked by `audioOnlyItemActive`).
    /// The caller is responsible for persisting `store.settings.audioOnlyMode`.
    @MainActor
    func toggleAudioOnlyLive() {
        let savedTime = currentTime
        isAudioOnlyMode.toggle()
        settings.audioOnlyMode = isAudioOnlyMode
        toastMessage =
            isAudioOnlyMode
            ? L10n.string("Audio-Only Mode")
            : L10n.string("Video Mode")

        if isAudioOnlyMode {
            // Overlay shows immediately via isAudioOnlyMode = true.
            // Attempt stream swap in background; failure does NOT revert the overlay.
            Task { [weak self] in
                guard let self else { return }
                await self.loadAudioOnlyItemIfEnabled(seekTo: savedTime, liveToggle: true)
            }
        } else {
            // Only reload HLS if we actually swapped to an audio-only stream;
            // otherwise HLS is already playing and no reload is needed.
            if audioOnlyItemActive {
                audioOnlyItemActive = false
                Task { [weak self] in
                    guard let self else { return }
                    // Restore the user's quality preference (fixes W6: passing nil dropped the preference).
                    await self.reloadHLSItem(seekTo: savedTime, quality: settings.preferredQuality)
                }
            }
        }
    }

    /// Entry point called from `loadAsync()` only when `isAudioOnlyMode == true`
    /// and `playerInfo` is already populated by the normal fetch.
    ///
    /// The existing HLS item is already loaded when this runs. If every audio-only
    /// attempt fails the HLS item remains active — the user gets video silently.
    /// - Parameter liveToggle: When `true` (called from `toggleAudioOnlyLive`), audio
    ///   load failures do NOT revert `isAudioOnlyMode` — the overlay stays visible with
    ///   HLS audio playing underneath. When `false` (new video load), failures silently
    ///   fall back to HLS and reset the flag.
    func loadAudioOnlyItemIfEnabled(seekTo seekTime: TimeInterval = 0, liveToggle: Bool = false) async {
        guard isAudioOnlyMode else { return }
        guard let info = playerInfo else { return }

        // Live streams have no adaptive audio-only URL. Leave HLS path untouched.
        guard !info.video.isLive else {
            audioOnlyLog.notice("Audio-only: skipped for live stream id=\(info.video.id)")
            return
        }

        // Attempt 1: iOS client URL (already in memory, zero extra network cost).
        if let url = info.bestAdaptiveAudioURL {
            let success = await tryLoadAudioURL(
                url, userAgent: InnerTubeClients.iOS.userAgent, seekTo: seekTime, liveToggle: liveToggle)
            if success { return }
            audioOnlyLog.notice("Audio-only: iOS client URL failed, retrying with android_vr")
        }

        // Attempt 2: android_vr client — no PO Token required for unauthenticated users.
        await retryAudioOnlyWithAndroidVR(videoId: info.video.id, seekTo: seekTime, liveToggle: liveToggle)
    }

    /// Builds an `AVURLAsset` for the given audio URL, checks playability, and replaces
    /// the current player item. Returns `true` on success.
    private func tryLoadAudioURL(
        _ url: URL, userAgent: String, seekTo seekTime: TimeInterval = 0, liveToggle: Bool = false
    ) async -> Bool {
        let opts: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]
        ]
        let asset = AVURLAsset(url: url, options: opts)
        guard (try? await asset.load(.isPlayable)) == true else { return false }

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral

        // Set up an item observer before replacing the current item, matching the
        // pattern used by every other load path. Without this the audio item's
        // .failed status is never observed, causing silent playback stalls.
        // BUG-009 fix: replace the current item BEFORE setting up the observer.
        audioOnlyItemActive = true
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream {
                guard let self, !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    audioOnlyLog.notice(
                        "[benchmark] readyToPlay — audio-only — videoId=\(self.currentVideo?.id ?? "nil") title=\(self.currentVideo?.title ?? "nil")"
                    )
                    audioOnlyLog.notice("✅ Audio-only AVPlayerItem readyToPlay")
                    if seekTime > 0 { self.seek(to: seekTime) }
                    self.player.rate = Float(self.settings.playbackSpeed)
                    self.isPlaying = true
                    self.loadAudioTracks(from: item)
                    // Dismiss the spinner — audio item is buffered and playing.
                    self.isLoading = false
                case .failed:
                    let err = item.error.map { "\($0)" } ?? "nil"
                    audioOnlyLog.error("❌ Audio-only AVPlayerItem failed: \(err)")
                    self.audioOnlyItemActive = false
                    // BUG-008 fix: only reset isAudioOnlyMode when this is NOT a live toggle.
                    // On liveToggle, the overlay stays visible with HLS audio underneath.
                    if !liveToggle {
                        self.isAudioOnlyMode = false
                    }
                    self.error = item.error
                case .unknown:
                    audioOnlyLog.notice("Audio-only: AVPlayerItem status unknown (loading)")
                @unknown default:
                    break
                }
            }
        }

        // BUG-010 fix: restart endObserverTask so autoplay-to-next works in audio-only mode.
        // The main loadAsync sets up endObserverTask for the HLS AVPlayerItem; when we replace
        // that item with an audio-only AVPlayerItem, the old observer watches the wrong object
        // and didPlayToEndTimeNotification is never delivered.
        endObserverTask?.cancel()
        endObserverTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.handlePlaybackEnd()
            }
        }

        audioOnlyLog.notice("Audio-only: loaded \(url.absoluteString.prefix(80))")
        return true
    }

    /// Fetches player info with the android_vr client and retries loading the audio URL.
    /// Falls back to the existing HLS item (already in player) on any failure.
    private func retryAudioOnlyWithAndroidVR(
        videoId: String, seekTo seekTime: TimeInterval = 0, liveToggle: Bool = false
    ) async {
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: videoId)
            if let url = vrInfo.bestAdaptiveAudioURL {
                let success = await tryLoadAudioURL(
                    url, userAgent: InnerTubeClients.AndroidVR.userAgent, seekTo: seekTime, liveToggle: liveToggle)
                if success { return }
            }
        } catch {
            audioOnlyLog.error("Audio-only: android_vr fetch failed: \(error)")
        }

        // Both attempts failed.
        audioOnlyItemActive = false
        if liveToggle {
            // Live toggle: keep overlay showing with HLS audio underneath.
            // Don't reset isAudioOnlyMode — the user's preference stays.
            audioOnlyLog.notice("Audio-only: all attempts failed (live toggle) — overlay stays, HLS audio continues")
            toastMessage = L10n.string("Audio-only stream unavailable — showing thumbnail")
        } else {
            // New video load: silently fall back to HLS video.
            audioOnlyLog.notice("Audio-only: all attempts failed, falling back to HLS")
            isAudioOnlyMode = false
        }
    }
}
