import SmartTubeIOSCore
import SwiftUI

// MARK: - ChannelView
//
// Displays channel info, subscriber count and a grid of recent uploads.
// Mirrors the Android `ChannelFragment`.

// MARK: - ChannelFilter

private enum ChannelFilter: String, CaseIterable {
    case all = "All"
    case shorts = "Shorts"

    var displayTitle: String {
        switch self {
        case .all: return L10n.string("All")
        case .shorts: return L10n.string("Shorts")
        }
    }
}

public struct ChannelView: View {
    public let channelId: String
    @State private var vm = ChannelViewModel()
    @State private var selectedVideo: Video?
    @State private var shortsPresentation: ShortsPresentation?
    @State private var channelDestination: ChannelDestination?
    @State private var filter: ChannelFilter = .all
    @State private var isFollowedLocally = false
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.isLandscapeLayout) private var isLandscapeLayout
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif

    public init(channelId: String) {
        self.channelId = channelId
    }

    public var body: some View {
        Group {
            if vm.isLoading && vm.channel == nil {
                ProgressView(L10n.string("Loading channel…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("channel.view")
            } else {
                content
            }
        }
        .navigationTitle(vm.channel?.title ?? L10n.string("Channel"))
        .onAppear { vm.load(channelId: channelId) }
        .task(id: vm.channel?.id) {
            guard let id = vm.channel?.id else { return }
            isFollowedLocally = await LocalSubscriptionStore.shared.isFollowing(id)
        }
        #if !os(iOS) && !os(macOS)
        .fullScreenCover(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        #if os(macOS)
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .navigationDestination(item: $channelDestination) { dest in
            ChannelView(channelId: dest.channelId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        #if !os(macOS)
        .fullScreenCover(item: $shortsPresentation) { target in
            ShortsPlayerView(videos: target.videos, startIndex: target.startIndex, api: api)
        }
        #endif
        .alert(L10n.string("Error"), isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button(L10n.string("Retry")) { vm.load(channelId: channelId) }
            Button(L10n.string("Dismiss"), role: .cancel) {}
        } message: { err in
            Text(err.localizedDescription)
        }
        .toolbar {
            if let channel = vm.channel {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    let isExcluded = store.settings.sponsorBlockExcludedChannels[channel.id] != nil
                    Button {
                        toggleSponsorBlockExclusion(for: channel)
                    } label: {
                        Label(
                            L10n.string(
                                isExcluded ? "Remove SponsorBlock Exclusion" : "Exclude from SponsorBlock"),
                            systemImage: isExcluded
                                ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus"
                        )
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    let isExcluded = store.settings.sponsorBlockExcludedChannels[channel.id] != nil
                    Button {
                        toggleSponsorBlockExclusion(for: channel)
                    } label: {
                        Label(
                            L10n.string(
                                isExcluded ? "Remove SponsorBlock Exclusion" : "Exclude from SponsorBlock"),
                            systemImage: isExcluded
                                ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus"
                        )
                    }
                    .accessibilityIdentifier("channel.sponsorBlockButton")
                }
                #endif
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Channel header
                if let channel = vm.channel {
                    channelHeader(channel)
                }

                // All / Shorts filter
                Picker(L10n.string("Filter"), selection: $filter) {
                    ForEach(ChannelFilter.allCases, id: \.self) { tab in
                        Text(tab.displayTitle).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .accessibilityIdentifier("channel.filterPicker")

                let filtered = filteredVideos
                if filter == .shorts {
                    shortsGrid(filtered)
                } else {
                    videosGrid(filtered)
                }

                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
        }
        .refreshable { vm.load(channelId: channelId) }
        .accessibilityIdentifier("channel.view")
    }

    // MARK: - Filtered data

    private var filteredVideos: [Video] {
        switch filter {
        case .all: return vm.videos.filter { !store.settings.hideShorts || !$0.isShort }
        case .shorts: return vm.shorts
        }
    }

    // MARK: - Grid layouts

    private func videosGrid(_ videos: [Video]) -> some View {
        let compact = store.settings.compactThumbnails
        return Group {
            if compact {
                LazyVStack(spacing: 0) {
                    ForEach(videos) { video in
                        VideoCardView(video: video, compact: true)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("video.card.\(video.id)")
                            .onTapGesture {
                                #if os(iOS)
                                playerRouter.open(video: video, api: api)
                                #else
                                selectedVideo = video
                                #endif
                            }
                            .onAppear {
                                if video.id == vm.videos.last?.id { vm.loadMore() }
                            }
                        Divider().padding(.horizontal)
                    }
                }
            } else {
                #if os(tvOS)
                let columnCount = 4
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stride(from: 0, to: videos.count, by: columnCount)), id: \.self) { startIdx in
                        let rowVideos = Array(videos[startIdx..<min(startIdx + columnCount, videos.count)])
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(rowVideos) { video in
                                VideoCardView(video: video, compact: false, onSelect: { selectedVideo = video })
                                    .frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("video.card.\(video.id)")
                            }
                            let remainder = columnCount - rowVideos.count
                            if remainder > 0 {
                                ForEach(0..<remainder, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .onAppear {
                            if rowVideos.last?.id == vm.videos.last?.id { vm.loadMore() }
                        }
                    }
                }
                .padding()
                #else
                LazyVGrid(
                    columns: videoGridColumns(store.settings, landscape: isLandscapeLayout),
                    spacing: videoGridRowSpacing
                ) {
                    ForEach(videos) { video in
                        VideoCardView(video: video, compact: false)
                            .accessibilityIdentifier("video.card.\(video.id)")
                            .onTapGesture {
                                #if os(iOS)
                                playerRouter.open(video: video, api: api)
                                #else
                                selectedVideo = video
                                #endif
                            }
                            .onAppear {
                                if video.id == vm.videos.last?.id { vm.loadMore() }
                            }
                    }
                }
                .id(isLandscapeLayout)  // reset on column-count change — see VideoGridSection (#82)
                .padding()
                #endif
            }
        }
    }

    private func shortsGrid(_ videos: [Video]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(videos) { video in
                VideoCardView(video: video)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .onTapGesture { selectShort(video, from: videos) }
            }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("channel.videoGrid")
    }

    private func selectShort(_ video: Video, from videos: [Video]) {
        let idx = videos.firstIndex(where: { $0.id == video.id }) ?? 0
        shortsPresentation = ShortsPresentation(videos: videos, startIndex: idx)
    }

    private func toggleSponsorBlockExclusion(for channel: Channel) {
        if store.settings.sponsorBlockExcludedChannels[channel.id] != nil {
            store.settings.sponsorBlockExcludedChannels.removeValue(forKey: channel.id)
        } else {
            store.settings.sponsorBlockExcludedChannels[channel.id] = channel.title
        }
    }

    private func channelHeader(_ channel: Channel) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: channel.thumbnailURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.secondary.opacity(0.3))
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("channel.title")
                if let subs = channel.subscriberCount {
                    Text(subs)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let desc = channel.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if !auth.isSignedIn {
                Button {
                    Task { await toggleFollow(channel) }
                } label: {
                    Label(
                        L10n.string(isFollowedLocally ? "Unfollow" : "Follow"),
                        systemImage: isFollowedLocally ? "bell.slash" : "bell"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("channel.followButton")
            }
        }
        .padding()
        .background(.background)
        .accessibilityIdentifier("channel.header")
    }

    private func toggleFollow(_ channel: Channel) async {
        if isFollowedLocally {
            await LocalSubscriptionStore.shared.unfollow(channelId: channel.id)
            isFollowedLocally = false
        } else {
            let local = LocalChannel(
                id: channel.id,
                title: channel.title,
                thumbnailURL: channel.thumbnailURL
            )
            await LocalSubscriptionStore.shared.follow(local)
            isFollowedLocally = true
        }
    }
}
