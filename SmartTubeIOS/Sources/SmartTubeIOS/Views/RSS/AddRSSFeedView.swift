import SmartTubeIOSCore
import SwiftUI

// MARK: - AddRSSFeedView

/// Sheet that lets the user add a new RSS feed URL.

struct AddRSSFeedView: View {
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("Feed Details")) {
                    TextField(L10n.string("Feed Title (e.g. Tech Reviews)"), text: $feedTitle)
                        .accessibilityIdentifier("rss.addFeed.titleField")
                    TextField(L10n.string("RSS Feed URL"), text: $feedURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("rss.addFeed.urlField")
                }

                Section {
                    Button {
                        addFeed()
                    } label: {
                        if isAdding {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Adding…", bundle: L10n.bundle)
                            }
                        } else {
                            Text("Add Feed", bundle: L10n.bundle)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(feedURL.isEmpty || feedTitle.isEmpty || isAdding)
                    .accessibilityIdentifier("rss.addFeed.confirmButton")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text(
                        "YouTube RSS feed URLs look like:\n**youtube.com/feeds/videos.xml?channel_id=…**\n\nYou can also find a channel's RSS feed via their channel page URL.",
                        bundle: L10n.bundle
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.string("Add RSS Feed"))
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func addFeed() {
        let trimmedURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedURL),
            url.scheme == "https" || url.scheme == "http"
        else {
            errorMessage = L10n.string("Please enter a valid https URL.")
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            let feed = RSSFeedInfo(title: trimmedTitle, feedURL: url)
            await RSSFeedStore.shared.addFeed(feed)
            dismiss()
        }
    }
}
