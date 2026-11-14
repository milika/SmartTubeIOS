import SmartTubeIOSCore
import SwiftUI

// MARK: - ManageRSSFeedsView

/// Sheet showing the list of saved RSS feeds with toggle-active and swipe-to-delete.

struct ManageRSSFeedsView: View {
    @State private var feeds: [RSSFeedInfo] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if feeds.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No RSS Feeds"),
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Add a feed from the RSS Feeds screen.", bundle: L10n.bundle)
                    )
                } else {
                    List {
                        ForEach(feeds) { feed in
                            feedRow(feed)
                        }
                        .onDelete(perform: deleteFeeds)
                    }
                }
            }
            .navigationTitle(L10n.string("Manage RSS Feeds"))
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done")) { dismiss() }
                }
            }
            .task {
                await reloadFeeds()
            }
        }
    }

    private func feedRow(_ feed: RSSFeedInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(feed.feedURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { feed.isActive },
                    set: { newValue in
                        Task {
                            await RSSFeedStore.shared.setActive(feed.id, newValue)
                            await reloadFeeds()
                        }
                    }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func deleteFeeds(at offsets: IndexSet) {
        let toDelete = offsets.map { feeds[$0] }
        Task {
            for feed in toDelete {
                await RSSFeedStore.shared.removeFeed(id: feed.id)
            }
            await reloadFeeds()
        }
    }

    @MainActor
    private func reloadFeeds() async {
        feeds = await RSSFeedStore.shared.allFeeds()
        isLoading = false
    }
}
