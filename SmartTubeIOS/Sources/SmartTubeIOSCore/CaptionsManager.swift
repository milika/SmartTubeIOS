import Foundation
import os

private let captionLog = Logger(subsystem: appSubsystem, category: "Captions")

// MARK: - CaptionsManager

/// Owns caption state: `availableCaptions`, `selectedCaption`, `currentCaptionCue`,
/// `captionCues`, and `captionFetchTask`. Fully self-contained — no delegate needed.
@MainActor
@Observable
public final class CaptionsManager {

    // MARK: - State

    public var availableCaptions: [CaptionTrack] = []
    public var selectedCaption: CaptionTrack? = nil
    public var currentCaptionCue: CaptionCue? = nil

    // Not observed (task handle, not UI state)
    @ObservationIgnored public var captionCues: [CaptionCue] = []
    @ObservationIgnored public var captionFetchTask: Task<Void, Never>? = nil

    // MARK: - Init

    public init() {}

    // MARK: - Interface

    public func reset() {
        availableCaptions = []
        selectedCaption = nil
        currentCaptionCue = nil
        captionCues = []
        captionFetchTask?.cancel()
        captionFetchTask = nil
    }

    public func cancel() {
        captionFetchTask?.cancel()
        captionFetchTask = nil
    }

    /// Selects a caption track and fetches its VTT cues. Pass `nil` to disable captions.
    /// `currentTime` is captured at call-time to update the cue immediately after fetch.
    public func selectCaption(_ track: CaptionTrack?, currentTime: TimeInterval = 0) {
        selectedCaption = track
        currentCaptionCue = nil
        captionCues = []
        captionFetchTask?.cancel()
        captionFetchTask = nil
        guard let track else { return }
        let timeToApply = currentTime
        captionFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let parser = WebVTTParser()
                let cues = try await parser.fetchCues(from: track.baseURL)
                guard !Task.isCancelled else { return }
                self.captionCues = cues
                captionLog.notice(
                    "loaded \(cues.count, privacy: .public) cues for \(track.languageCode, privacy: .public)"
                )
                self.updateCaptionCue(for: timeToApply)
            } catch {
                // Caption fetch failed — leave cues empty, but make the failure
                // visible in the device log (this is the only way to tell a
                // missing track apart from a blocked timedtext request).
                captionLog.error(
                    "fetch/parse failed for \(track.languageCode, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Updates `currentCaptionCue` for the given playback position.
    public func updateCaptionCue(for time: TimeInterval) {
        guard !captionCues.isEmpty else {
            currentCaptionCue = nil
            return
        }
        currentCaptionCue = captionCues.last(where: { $0.startTime <= time && $0.endTime > time })
    }
}
