import SmartTubeIOSCore
import SwiftUI

// MARK: - PlaylistPickerSheet (#8 — move/copy videos between playlists)
//
// Presented from VideoCardView's "Copy to Playlist" / "Move to Playlist" context menu
// actions. Lists the user's playlists (fetched live — there's no local cache of them),
// lets them pick a destination, and performs the add (copy) or add+remove (move).

struct PlaylistPickerSheet: View {
    enum Mode: Identifiable {
        case copy
        case move

        var id: Self { self }
    }

    let mode: Mode
    let video: Video
    /// The playlist this card is currently being browsed from, if any. Excluded from the
    /// destination list (copying/moving a video into the playlist it's already in is a no-op),
    /// and required (along with `video.setVideoId`) for `.move` to know what to remove from.
    let sourcePlaylistId: String?
    let api: InnerTubeAPI
    let onFinished: (Result<PlaylistInfo, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [PlaylistInfo] = []
    @State private var isLoading = true
    @State private var loadErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let loadErrorMessage {
                    ContentUnavailableView(
                        String(localized: "Could Not Load Playlists", bundle: .module),
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadErrorMessage)
                    )
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Playlists", bundle: .module),
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    List(playlists) { playlist in
                        Button {
                            select(playlist)
                        } label: {
                            HStack {
                                Text(playlist.title)
                                Spacer()
                                if let count = playlist.videoCount {
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
            .navigationTitle(
                mode == .copy
                    ? String(localized: "Copy to Playlist", bundle: .module)
                    : String(localized: "Move to Playlist", bundle: .module)
            )
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @State private var isSubmitting = false

    private func load() async {
        do {
            var fetched = try await api.fetchUserPlaylists()
            if let sourcePlaylistId {
                fetched.removeAll { $0.id == sourcePlaylistId }
            }
            playlists = fetched
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func select(_ playlist: PlaylistInfo) {
        isSubmitting = true
        Task {
            do {
                try await api.addToPlaylist(playlistId: playlist.id, videoId: video.id)
                if playlist.id == "WL" { WatchLaterMembershipStore.shared.markSaved(video.id) }
                if mode == .move, let sourcePlaylistId, let setVideoId = video.setVideoId {
                    try await api.removeFromPlaylist(playlistId: sourcePlaylistId, setVideoId: setVideoId)
                    if sourcePlaylistId == "WL" { WatchLaterMembershipStore.shared.markRemoved(video.id) }
                }
                onFinished(.success(playlist))
            } catch {
                onFinished(.failure(error))
            }
            dismiss()
        }
    }
}
