import SmartTubeIOSCore
import SwiftUI

// MARK: - ChannelListView
//
// Displays the list of channels the authenticated user subscribes to.
// Shown when the "Channels" chip is selected in the Home chip bar.
// Mirrors the Android ChannelsBrowseFragment channel row layout.

struct ChannelListView: View {
    let channels: [Channel]
    let onSelect: (Channel) -> Void
    #if os(tvOS)
    @FocusState private var focusedChannelId: String?
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(channels) { channel in
                    #if os(tvOS)
                    Button {
                        onSelect(channel)
                    } label: {
                        ChannelListRow(channel: channel)
                            .background(
                                focusedChannelId == channel.id
                                    ? Color.primary.opacity(0.12)
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedChannelId, equals: channel.id)
                    #else
                    ChannelListRow(channel: channel)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(channel) }
                    #endif
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

// MARK: - ChannelListRow

private struct ChannelListRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title.isEmpty ? L10n.string("Unknown channel") : channel.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let count = channel.subscriberCount {
                    Text(count)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = channel.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: 48, height: 48)
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: AppSymbol.personCircle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}
