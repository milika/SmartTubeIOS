// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import Foundation

#if canImport(ActivityKit)
import ActivityKit

// MARK: - DownloadActivityAttributes
//
// Defines the Live Activity / Dynamic Island data model for video downloads.
// Both VideoDownloadService (SmartTubeIOS) and the DownloadWidget extension
// reference this type so the content must match exactly.
//
// Static attributes (set once when the activity is requested):
//   videoTitle — shown in the Dynamic Island and Lock Screen banner
//
// Dynamic content state (updated during the download):
//   phase    — current pipeline stage
//   progress — 0.0–1.0; meaningful only during .downloading

@available(iOS 16.1, macCatalyst 16.1, *)
@available(macOS, unavailable)
public struct DownloadActivityAttributes: ActivityAttributes {
    public typealias ContentState = DownloadContentState

    public struct DownloadContentState: Codable, Hashable, Sendable {
        public var progress: Double
        public var phase: Phase

        public enum Phase: String, Codable, Hashable, Sendable {
            case fetching
            case downloading
            case saving
            case done
            case failed
        }

        public init(progress: Double = 0, phase: Phase = .fetching) {
            self.progress = progress
            self.phase = phase
        }
    }

    public var videoTitle: String

    public init(videoTitle: String) {
        self.videoTitle = videoTitle
    }
}
#endif
#endif  // ENABLE_DOWNLOADS
