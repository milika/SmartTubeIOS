import Foundation
import SmartTubeIOSCore

// MARK: - Caption Track Selection (thin wrapper — logic lives in CaptionsManager)

extension PlaybackViewModel {

    public func selectCaption(_ track: CaptionTrack?) {
        applyCaption(track)
        // Persist the user's choice so it can be re-applied to the next video.
        // nil means "captions off" and clears the preference.
        settings.preferredCaptionLanguage = track?.languageCode
    }

    /// One-tap CC toggle for the quick-access row. Unlike `selectCaption(nil)`,
    /// turning off keeps the persisted preference and the last track so the
    /// next tap can restore them.
    public func toggleCaptions() {
        if selectedCaption != nil {
            captionsManager.selectCaption(nil, currentTime: currentTime)
            return
        }
        if let last = lastSelectedCaption,
            availableCaptions.contains(where: { $0.id == last.id })
        {
            captionsManager.selectCaption(last, currentTime: currentTime)
            return
        }
        if let code = settings.preferredCaptionLanguage, !code.isEmpty,
            let match = caption(for: code)
        {
            captionsManager.selectCaption(match, currentTime: currentTime)
            return
        }
        if let first = availableCaptions.first {
            captionsManager.selectCaption(first, currentTime: currentTime)
        }
    }

    private func applyCaption(_ track: CaptionTrack?) {
        if let track { lastSelectedCaption = track }
        captionsManager.selectCaption(track, currentTime: currentTime)
    }

    private func caption(for languageCode: String) -> CaptionTrack? {
        let base = languageCode.components(separatedBy: "-").first ?? languageCode
        return availableCaptions.first(where: { $0.languageCode == languageCode })
            ?? availableCaptions.first(where: { $0.languageCode.hasPrefix(base) })
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
        // Exact match first, then BCP-47 prefix match (e.g. "en" matches "en-US").
        let base = code.components(separatedBy: "-").first ?? code
        if let match = tracks.first(where: { $0.languageCode == code })
            ?? tracks.first(where: { $0.languageCode.hasPrefix(base) })
        {
            captionsManager.selectCaption(match, currentTime: currentTime)
        }
        // No match: leave captions off rather than forcing a wrong language.
    }
}
