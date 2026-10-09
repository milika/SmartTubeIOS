// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import Foundation
import Observation

// MARK: - DownloadedVideo

/// A record representing a video that has been downloaded to the device's local storage.
/// Persisted in `Documents/SmartTubeDownloads/manifest.json`.
public struct DownloadedVideo: Codable, Sendable, Identifiable {
    public var id: String { videoId }
    public let videoId: String
    public let title: String
    public let channelTitle: String
    public let thumbnailURL: URL?
    public let duration: Double
    public let fileURL: URL
    public let downloadedAt: Date

    public init(
        videoId: String,
        title: String,
        channelTitle: String,
        thumbnailURL: URL?,
        duration: Double,
        fileURL: URL,
        downloadedAt: Date
    ) {
        self.videoId = videoId
        self.title = title
        self.channelTitle = channelTitle
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.fileURL = fileURL
        self.downloadedAt = downloadedAt
    }

    /// Synthesises a `Video` value with `localFileURL` set to `fileURL`,
    /// suitable for handing to `PlaybackViewModel.load(video:)`.
    public var video: Video {
        var v = Video(
            id: videoId,
            title: title,
            channelTitle: channelTitle,
            thumbnailURL: thumbnailURL,
            duration: duration
        )
        v.localFileURL = fileURL
        return v
    }
}

// MARK: - DownloadStore

/// Persistent in-app registry of downloaded videos.
///
/// Downloaded MP4s are stored under `Documents/SmartTubeDownloads/<videoId>.mp4`.
/// A JSON manifest (`manifest.json` in the same directory) records metadata for
/// each download so the `DownloadsView` can display title, thumbnail, and duration
/// without opening each MP4.
///
/// `VideoDownloadService` calls `add(_:)` after a successful save.
/// `DownloadsView` calls `remove(videoId:)` when the user swipes to delete.
/// `PlaybackViewModel+Loading` reads `Video.localFileURL` (populated by
/// `DownloadedVideo.video`) to skip the network fetch entirely.
@Observable
@MainActor
public final class DownloadStore {
    public static let shared = DownloadStore()

    public private(set) var entries: [DownloadedVideo] = []

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartTubeDownloads")
    }

    private var manifestURL: URL {
        downloadsDirectory.appendingPathComponent("manifest.json")
    }

    private init() {
        loadManifest()
    }

    // MARK: - Public API

    /// The on-disk destination for a downloaded video.
    /// Percent-encodes the `videoId` to guarantee a 1-to-1 mapping between any
    /// video ID and its filename — avoids the theoretical collision that could
    /// occur when two IDs differ only in special characters stripped by a
    /// character-filter approach. For standard YouTube 11-char IDs
    /// (`[A-Za-z0-9_-]`) the result is identical to the raw ID.
    public func destinationURL(for videoId: String) -> URL {
        let encoded = videoId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? videoId
        return downloadsDirectory.appendingPathComponent("\(encoded).mp4")
    }

    /// Adds or replaces a download record and persists the manifest.
    public func add(_ entry: DownloadedVideo) {
        entries.removeAll { $0.videoId == entry.videoId }
        entries.append(entry)
        saveManifest()
    }

    /// Deletes the MP4 file and removes the record from the manifest.
    public func remove(videoId: String) {
        if let entry = entries.first(where: { $0.videoId == videoId }) {
            try? FileManager.default.removeItem(at: entry.fileURL)
        }
        entries.removeAll { $0.videoId == videoId }
        saveManifest()
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
            let decoded = try? JSONDecoder().decode([DownloadedVideo].self, from: data)
        else {
            return
        }
        // Migrate entries whose stored fileURL no longer exists on disk.
        // The old destinationURL used a character-filter sanitiser; the new one uses
        // percent-encoding. For standard YouTube IDs these are identical, but migrate
        // any edge-case entries by trying the new path before dropping them.
        let fm = FileManager.default
        var migrated: [DownloadedVideo] = []
        for entry in decoded {
            if fm.fileExists(atPath: entry.fileURL.path) {
                migrated.append(entry)
            } else {
                let newURL = destinationURL(for: entry.videoId)
                if fm.fileExists(atPath: newURL.path) {
                    var updated = entry
                    // DownloadedVideo is a struct — recreate with the corrected fileURL.
                    let corrected = DownloadedVideo(
                        videoId: entry.videoId,
                        title: entry.title,
                        channelTitle: entry.channelTitle,
                        thumbnailURL: entry.thumbnailURL,
                        duration: entry.duration,
                        fileURL: newURL,
                        downloadedAt: entry.downloadedAt
                    )
                    _ = updated  // silence unused warning
                    migrated.append(corrected)
                }
                // If neither path exists, the file was deleted — drop the entry.
            }
        }
        entries = migrated
    }

    private func saveManifest() {
        let fm = FileManager.default
        try? fm.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
#endif  // ENABLE_DOWNLOADS
