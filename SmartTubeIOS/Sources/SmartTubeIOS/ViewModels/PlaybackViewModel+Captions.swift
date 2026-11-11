import Foundation
import SmartTubeIOSCore

// MARK: - Caption Track Selection (thin wrapper — logic lives in CaptionsManager)

extension PlaybackViewModel {

    public func selectCaption(_ track: CaptionTrack?) {
        captionsManager.selectCaption(track, currentTime: currentTime)
        // Persist the user's choice so it can be re-applied to the next video.
        // nil means "captions off" and clears the preference.
        settings.preferredCaptionLanguage = track?.languageCode
    }

    func updateCaptionCue(for time: TimeInterval) {
        captionsManager.updateCaptionCue(for: time)
    }

    /// Applies the saved caption language preference to the available tracks.
    /// Call this after `availableCaptions` is populated on video load.
    /// Does nothing when `preferredCaptionLanguage` is nil (captions stay off).
    func autoApplyCaptionPreference(tracks: [CaptionTrack]) {
        guard let code = settings.preferredCaptionLanguage, !code.isEmpty, !tracks.isEmpty else {
            return
        }
        if let match = CaptionTrack.matching(code, in: tracks) {
            captionsManager.selectCaption(match, currentTime: currentTime)
        }
        // No match: leave captions off rather than forcing a wrong language.
    }
}
