import SmartTubeIOSCore
import SwiftUI

// MARK: - ChannelSwitcherView
//
// Lists the signed-in account's channels (primary + Brand Accounts) and switches the
// active one. Feed view models reload on `.activeChannelDidChange`.

struct ChannelSwitcherView: View {
    @Environment(AuthService.self) private var auth
    @State private var showSignIn = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                ContentUnavailableView {
                    Label(L10n.string("Not Signed In"), systemImage: AppSymbol.channel)
                } description: {
                    Text("Sign in to switch between your channels.", bundle: L10n.bundle)
                } actions: {
                    Button(L10n.string("Sign in with Google")) { showSignIn = true }
                }
            } else if auth.channels.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        L10n.string("No Channels"),
                        systemImage: AppSymbol.channel,
                        description: Text("Could not load the channels of this account.", bundle: L10n.bundle)
                    )
                }
            } else {
                List(auth.channels.filter(\.isPrimary) + auth.channels.filter { !$0.isPrimary }) { channel in
                    channelRow(channel)
                }
            }
        }
        .navigationTitle(L10n.string("Channel"))
        .sheet(isPresented: $showSignIn) { SignInView() }
        .task(id: auth.isSignedIn) {
            isLoading = true
            await auth.loadChannelsIfNeeded()
            isLoading = false
        }
    }

    private func channelRow(_ channel: YouTubeChannel) -> some View {
        Button {
            auth.selectChannel(channel)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: channel.avatarURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color.secondary.opacity(0.3))
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .foregroundStyle(.primary)
                    if channel.isPrimary {
                        Text("Primary account", bundle: L10n.bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if channel.pageId == auth.activePageId {
                    Image(systemName: AppSymbol.checkmark)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
