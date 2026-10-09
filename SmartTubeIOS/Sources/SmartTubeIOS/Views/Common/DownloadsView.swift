// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import SmartTubeIOSCore
import SwiftUI

// MARK: - DownloadsView

/// Shows videos that have been downloaded to the device via VideoDownloadService.
/// Each row displays the thumbnail, title, channel, duration, file size, and
/// download date. Tapping a row plays the video from the local file (no network
/// required). Swipe-to-delete removes both the MP4 and the DownloadStore record.

struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloadStore

    #if os(iOS)
    @Environment(PlayerStateStore.self) private var playerState
    #else
    @State private var selectedVideo: Video?
    #endif

    @State private var deleteConfirmationVideoId: String?

    var body: some View {
        #if os(iOS)
        iOSBody
        #else
        tvOSBody
        #endif
    }

    #if os(iOS)
    private var iOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            if downloadStore.entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(downloadStore.entries.sorted { $0.downloadedAt > $1.downloadedAt }) { entry in
                        DownloadedVideoRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerState.play(video: entry.video)
                            }
                            .accessibilityIdentifier("downloads.videoRow.\(entry.videoId)")
                    }
                    .onDelete { indexSet in
                        let sorted = downloadStore.entries.sorted { $0.downloadedAt > $1.downloadedAt }
                        for idx in indexSet {
                            deleteConfirmationVideoId = sorted[idx].videoId
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert(
            "Delete Download",
            isPresented: Binding(
                get: { deleteConfirmationVideoId != nil },
                set: { if !$0 { deleteConfirmationVideoId = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let vid = deleteConfirmationVideoId {
                    downloadStore.remove(videoId: vid)
                }
                deleteConfirmationVideoId = nil
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmationVideoId = nil
            }
        } message: {
            Text("This video will be removed from your device. You can re-download it from the player.")
        }
    }
    #else
    private var tvOSBody: some View {
        emptyState
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.to.line.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Downloaded Videos")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Download a video from the player to watch it offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.emptyState")
    }
}

// MARK: - DownloadedVideoRow

private struct DownloadedVideoRow: View {
    let entry: DownloadedVideo

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var fileSizeDescription: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: entry.fileURL.path),
            let bytes = attrs[.size] as? Int64
        else { return "" }
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    private var durationDescription: String {
        guard entry.duration > 0 else { return "" }
        let mins = Int(entry.duration) / 60
        let secs = Int(entry.duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: entry.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().foregroundStyle(.secondary.opacity(0.3))
                }
            }
            .frame(width: 100, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(entry.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !durationDescription.isEmpty {
                        Text(durationDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !fileSizeDescription.isEmpty {
                        Text(fileSizeDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.dateFormatter.string(from: entry.downloadedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
#endif  // ENABLE_DOWNLOADS
