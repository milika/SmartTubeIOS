import SmartTubeIOSCore
import SwiftUI

// MARK: - RSSFeedsView

/// Shows videos from all active user-added RSS feed subscriptions.
/// Mimics the queue/playlist layout (compact card list, newest-first).

struct RSSFeedsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var vm = RSSFeedsViewModel()
    @State private var showAddFeed = false
    @State private var showManageFeeds = false

    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #else
    @State private var selectedVideo: Video?
    #endif
    @Environment(\.innerTubeAPI) private var api

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Inline header — shown because LibraryView hides the navigation bar globally.
            HStack {
                Text("RSS Feeds", bundle: L10n.bundle)
                    .font(.headline)
                Spacer()
                Button {
                    showManageFeeds = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel(L10n.string("Manage RSS Feeds"))
                .accessibilityIdentifier("rss.manageFeedsButton")
                Button {
                    showAddFeed = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("Add RSS Feed"))
                .accessibilityIdentifier("rss.addFeedButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            #endif

            Group {
                if vm.isLoading && vm.videos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.videos.isEmpty {
                    emptyState
                } else {
                    videoList
                }
            }
        }
        .sheet(isPresented: $showAddFeed, onDismiss: { vm.load() }) {
            AddRSSFeedView()
        }
        .sheet(isPresented: $showManageFeeds, onDismiss: { vm.load() }) {
            ManageRSSFeedsView()
        }
        #if os(tvOS)
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .task {
            vm.load()
        }
        .refreshable {
            vm.load()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No RSS Feeds", bundle: L10n.bundle)
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add a YouTube channel RSS feed to see videos here.", bundle: L10n.bundle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddFeed = true
            } label: {
                Label(L10n.string("Add RSS Feed"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("rss.emptyAddFeedButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Video List

    private var videoList: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let displayVideos = vm.videos
            .filter { !hideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
        return ScrollView {
            VideoGridSection(
                videos: displayVideos,
                onSelect: { video in
                    #if os(iOS)
                    playerRouter.open(video: video, api: api)
                    #else
                    selectedVideo = video
                    #endif
                }
            )
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }
}
