import SmartTubeIOSCore
import SwiftUI

#if !os(tvOS)

// MARK: - ⋯ menu

/// What a row of the Shorts ⋯ menu asks the player to do. Settings rows (captions,
/// speed, auto-scroll) change `AppSettings` directly instead.
enum ShortsMenuAction {
    case description
    case saveToPlaylist
    case clearScreen
    case notInterested
    case dontRecommendChannel
    case report
}

/// The ⋯ sheet, laid out like the official app's: actions first, then settings, then
/// the feedback actions, then Cancel.
struct ShortsMoreSheet: View {
    /// Save/Not interested/Don't recommend need an account, so they're hidden signed out.
    let isSignedIn: Bool
    /// Whether the Short's channel is known ("Don't recommend channel" needs it).
    let hasChannel: Bool
    let onAction: (ShortsMenuAction) -> Void

    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                actionRow(.description, "Description", AppSymbol.description, AccessibilityID.Shorts.descriptionAction)
                if isSignedIn {
                    actionRow(
                        .saveToPlaylist, "Save to Playlist", AppSymbol.saveToPlaylist,
                        AccessibilityID.Shorts.saveToPlaylistAction)
                }
                actionRow(.clearScreen, "Clear Screen", AppSymbol.clearScreen, AccessibilityID.Shorts.clearScreenAction)
            }
            Section {
                Toggle(isOn: $store.settings.shortsCaptions) {
                    Label {
                        Text("Captions", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.captions)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Shorts.captionsAction)
                Picker(selection: $store.settings.playbackSpeed) {
                    ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                        Text(Self.speedLabel(speed)).tag(speed)
                    }
                } label: {
                    Label {
                        Text("Playback Speed", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.playbackSpeed)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(AccessibilityID.Shorts.playbackSpeedAction)
                Toggle(isOn: $store.settings.shortsAutoScroll) {
                    Label {
                        Text("Auto-scroll", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.autoScroll)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Shorts.autoScrollToggle)
            }
            Section {
                if isSignedIn {
                    actionRow(
                        .notInterested, "Not Interested", AppSymbol.notInterested,
                        AccessibilityID.Shorts.notInterestedAction)
                }
                if isSignedIn && hasChannel {
                    actionRow(
                        .dontRecommendChannel, "Don't Recommend Channel", AppSymbol.dontRecommendChannel,
                        AccessibilityID.Shorts.dontRecommendChannelAction)
                }
                actionRow(.report, "Report on YouTube", AppSymbol.report, AccessibilityID.Shorts.reportAction)
            }
            Section {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module).frame(maxWidth: .infinity)
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(AccessibilityID.Shorts.moreSheet)
    }

    private func actionRow(
        _ action: ShortsMenuAction, _ title: LocalizedStringKey, _ symbol: String, _ id: String
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: symbol)
            }
        }
        .accessibilityIdentifier(id)
    }

    /// "1×" style, "Normal" for 1.
    static func speedLabel(_ speed: Double) -> String {
        speed == 1 ? String(localized: "Normal", bundle: .module) : "\(speed.formatted())\u{d7}"
    }
}

// MARK: - Description

/// The official Description sheet: title, channel, Likes/Views/date tiles and the
/// description text, loaded when opened.
struct ShortsDescriptionSheet: View {
    let videoId: String
    /// Shown until the description arrives (and if it can't be loaded).
    let fallback: ShortMetadata?
    let api: InnerTubeAPI
    let onOpenChannel: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description: ShortDescription?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .textSelection(.enabled)
                    channelRow
                    if let factoids = description?.factoids, !factoids.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(factoids, id: \.self) { factoid in tile(factoid) }
                        }
                    }
                    content
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text("Description", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: closePlacement) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: AppSymbol.xmark)
                    }
                    .accessibilityLabel(Text("Close", bundle: .module))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .accessibilityIdentifier(AccessibilityID.Shorts.descriptionSheet)
        .task(id: videoId) { await load() }
    }

    /// `.topBarTrailing` is UIKit-only; native macOS gets the standard dismiss slot.
    private var closePlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .cancellationAction
        #endif
    }

    private var title: String {
        if let title = description?.title, !title.isEmpty { return title }
        return fallback?.title ?? ""
    }

    private var channelRow: some View {
        let name = description?.channelTitle ?? fallback?.channelTitle ?? ""
        let avatar = description?.channelAvatarURL ?? fallback?.channelAvatarURL
        let channelId = description?.channelId ?? fallback?.channelId
        return Button {
            if let channelId { onOpenChannel(channelId) }
        } label: {
            HStack(spacing: 10) {
                AsyncImage(url: avatar) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(channelId == nil)
    }

    private func tile(_ factoid: ShortDescription.Factoid) -> some View {
        VStack(spacing: 2) {
            Text(factoid.value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(factoid.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(factoid.accessibilityText ?? "\(factoid.value) \(factoid.label)")
    }

    @ViewBuilder
    private var content: some View {
        if let text = description?.descriptionText, !text.isEmpty {
            Text(Self.linkified(text))
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        } else if description == nil && !loadFailed {
            ProgressView().frame(maxWidth: .infinity)
        } else if loadFailed {
            Text("Couldn't load the description.", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            description = try await api.fetchShortDescription(videoId: videoId)
        } catch {
            loadFailed = true
        }
    }

    /// Makes the description's URLs tappable.
    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: attributed) else { continue }
            attributed[range].link = url
        }
        return attributed
    }
}

#endif
