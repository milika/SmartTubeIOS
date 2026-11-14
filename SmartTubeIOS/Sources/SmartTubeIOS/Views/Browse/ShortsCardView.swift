import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsCardView
//
// Portrait (9:16) card for a single YouTube Short.
// Shows the thumbnail cropped to portrait with a dark gradient overlay
// and the title text at the bottom.  Used inside ShortsRowSection.

struct ShortsCardView: View {
    let video: Video
    let onTap: () -> Void

    @Environment(AuthService.self) private var authService
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @State private var watchLaterAlert: DownloadAlertItem?
    #if !os(tvOS)
    #if ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) private var downloadService
    #endif
    #endif

    /// Primary thumbnail URL: portrait oardefault.jpg when the API provided one
    /// (reelItemRenderer), landscape thumbnailURL otherwise.
    /// YouTube returns HTTP 200 with a blank black image for oardefault.jpg when
    /// no portrait thumbnail exists, so we skip it for non-reelItemRenderer Shorts.
    private var primaryURL: URL? {
        video.hasPortraitThumbnail ? video.portraitThumbnailURL : video.thumbnailURL
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ThumbnailFillView(primaryURL: primaryURL, fallbackURLs: video.thumbnailFallbackURLs)

            // Dark gradient + title overlay at the bottom.
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .overlay(alignment: .bottomLeading) {
                Text(video.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            let dur = video.formattedDuration
            if !dur.isEmpty {
                Text(dur)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            #if !os(tvOS)
            if let shareURL = video.shareURL {
                ShareLink(item: shareURL) {
                    Label(L10n.string("Share"), systemImage: AppSymbol.share)
                }
            }
            #endif
            if let channelId = video.channelId, !channelId.isEmpty {
                Button {
                    NotificationCenter.default.post(
                        name: .openChannel,
                        object: nil,
                        userInfo: ["channelId": channelId, "channelTitle": video.channelTitle]
                    )
                } label: {
                    Label(L10n.string("Open Channel"), systemImage: AppSymbol.personRectangle)
                }
            }
            if authService.isSignedIn {
                Button {
                    Task {
                        do {
                            try await api.addToWatchLater(videoId: video.id)
                            watchLaterAlert = DownloadAlertItem(
                                title: L10n.string("Saved to Watch Later"),
                                message: L10n.string("\"\(video.title)\" was added to your Watch Later playlist.")
                            )
                        } catch {
                            watchLaterAlert = DownloadAlertItem(
                                title: L10n.string("Could Not Save"),
                                message: error.localizedDescription
                            )
                        }
                    }
                } label: {
                    Label(L10n.string("Save to Watch Later"), systemImage: AppSymbol.watchLater)
                }
            }
            Button {
                Task { await CurrentQueueStore.shared.append(video) }
            } label: {
                Label(L10n.string("Add to Queue"), systemImage: "text.badge.plus")
            }
            Button {
                Task {
                    let count = await CurrentQueueStore.shared.videos.count
                    await CurrentQueueStore.shared.insertNext(video, afterIndex: count - 1)
                }
            } label: {
                Label(L10n.string("Play Next"), systemImage: "text.insert")
            }
            if authService.isSignedIn {
                Button(role: .destructive) {
                    Task {
                        if let token = video.notInterestedToken {
                            try? await api.sendFeedback(token: token)
                        } else {
                            try? await api.sendFeedbackForVideo(videoId: video.id, iconType: "NOT_INTERESTED")
                        }
                        NotificationCenter.default.post(
                            name: .hideVideoFromFeed,
                            object: nil,
                            userInfo: ["videoId": video.id]
                        )
                    }
                } label: {
                    Label(L10n.string("Not Interested"), systemImage: "hand.raised")
                }
                Button(role: .destructive) {
                    Task {
                        if let token = video.dontLikeToken {
                            try? await api.sendFeedback(token: token)
                        } else {
                            try? await api.sendFeedbackForVideo(videoId: video.id, iconType: "DISLIKE")
                        }
                        NotificationCenter.default.post(
                            name: .hideVideoFromFeed,
                            object: nil,
                            userInfo: ["videoId": video.id]
                        )
                    }
                } label: {
                    Label(L10n.string("Don't Like This Video"), systemImage: "hand.thumbsdown")
                }
                if let channelId = video.channelId, !channelId.isEmpty {
                    Button(role: .destructive) {
                        Task {
                            if let token = video.hideChannelToken {
                                try? await api.sendFeedback(token: token)
                            } else {
                                try? await api.sendFeedbackForVideo(videoId: video.id, iconType: "BLOCK_CHANNEL")
                            }
                            store.settings.blockedChannels[channelId] = video.channelTitle
                            NotificationCenter.default.post(
                                name: .hideChannelFromFeed,
                                object: nil,
                                userInfo: ["channelId": channelId]
                            )
                        }
                    } label: {
                        Label(L10n.string("Don't Recommend Channel"), systemImage: "person.slash")
                    }
                }
            }
            #if !os(tvOS) && ENABLE_DOWNLOADS
            Button {
                downloadService.download(video: video)
            } label: {
                if downloadService.state.isActive {
                    Label(L10n.string("Downloading…"), systemImage: AppSymbol.download)
                } else {
                    Label(L10n.string("Download to Gallery"), systemImage: AppSymbol.download)
                }
            }
            .disabled(downloadService.state.isActive)
            #endif
        }
        .alert(item: $watchLaterAlert) { item in
            Alert(
                title: Text(item.title), message: Text(item.message),
                dismissButton: .default(Text("OK", bundle: L10n.bundle)))
        }
    }
}
