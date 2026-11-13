import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Gesture exclusion regions

/// Window-space frames of the overlay's controls. `SwipeGestureOverlay`'s
/// window-level recognizers skip touches inside them, so tapping Like doesn't also
/// pause the Short and dragging the progress bar doesn't swipe to the next one.
struct ShortsInteractiveFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Registers this view's frame as a Shorts overlay control (see `ShortsInteractiveFramesKey`).
    func shortsInteractiveRegion() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ShortsInteractiveFramesKey.self, value: [geo.frame(in: .global)])
            }
        }
    }
}

/// Sheets the Shorts overlay can present.
enum ShortsSheet: String, Identifiable {
    case comments
    case more
    case description
    case saveToPlaylist
    var id: String { rawValue }

    /// Half-height sheets the video shrinks above, like the official app.
    var shrinksVideo: Bool { self == .comments || self == .description }
}

extension ShortsPlayerView {

    // MARK: - Index badge (UI tests only)
    //
    // The official Shorts UI has no position counter, but the hermetic UI tests read
    // `shorts.indexLabel` ("1 / 3"), so it is rendered only under `--uitesting`.

    @ViewBuilder
    var indexBadge: some View {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            Text(videos.isEmpty ? "0 / 0" : "\(currentIndex + 1) / \(videos.count)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())
                .accessibilityIdentifier(AccessibilityID.Shorts.indexLabel)
                .padding(.top, 12)
                .padding(.trailing, 20)
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    var shortsOverlay: some View {
        #if os(tvOS)
        // tvOS keeps the minimal overlay (navigation is via .onMoveCommand).
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer()
        }
        .contentShape(Rectangle())
        #else
        officialStyleOverlay
        #endif
    }

    var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: AppSymbol.chevronLeft)
                .font(.title2)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.4))
                .clipShape(Circle())
        }
        .accessibilityLabel("Back")
        .accessibilityIdentifier(AccessibilityID.Shorts.backButton)
    }

    #if !os(tvOS)

    /// Current Short's metadata, falling back to what the feed already knows.
    var currentMetadata: ShortMetadata? {
        guard let video = currentVideo else { return nil }
        return feed.displayMetadata(for: video)
    }

    // Official layout: top bar, then info panel (bottom-left) beside the action rail
    // (bottom-right), then a thin progress bar along the bottom edge. Only the
    // controls are hit-testable; everything else falls through to the gesture layer.
    private var officialStyleOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .allowsHitTesting(false)

            if showsPausedIndicator {
                Image(systemName: AppSymbol.playFill)
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                HStack {
                    if mode == .presented {
                        backButton.shortsInteractiveRegion()
                    }
                    Spacer()
                    if mode == .tab {
                        searchButton.shortsInteractiveRegion()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
                if let metadata = currentMetadata {
                    HStack(alignment: .bottom, spacing: 12) {
                        infoPanel(metadata)
                        Spacer(minLength: 0)
                        actionRail(metadata)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                progressBar
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showsPausedIndicator)
    }

    private var showsPausedIndicator: Bool {
        #if os(iOS)
        vm.playerState == .paused && !vm.videoEnded
        #else
        false
        #endif
    }

    private var searchButton: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: AppSymbol.search)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Search", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.Shorts.searchButton)
    }

    // MARK: Info panel (bottom-left)

    private func infoPanel(_ metadata: ShortMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    openChannel(metadata.channelId)
                } label: {
                    HStack(spacing: 8) {
                        AsyncImage(url: metadata.channelAvatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.white.opacity(0.25))
                        }
                        // The overlay outlives a swipe; without a new identity AsyncImage
                        // can keep the previous channel's avatar.
                        .id(metadata.channelAvatarURL)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        Text(metadata.channelTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(metadata.channelId == nil)
                .accessibilityIdentifier(AccessibilityID.Shorts.channelButton)

                if metadata.channelId != nil {
                    Button {
                        Task {
                            await feed.toggleSubscription(videoId: metadata.videoId, signedIn: authService.isSignedIn)
                        }
                    } label: {
                        Text(metadata.isSubscribed ? "Subscribed" : "Subscribe")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(metadata.isSubscribed ? .white : .black)
                            .background(metadata.isSubscribed ? Color.white.opacity(0.25) : Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Shorts.subscribeButton)
                }
            }

            if !metadata.title.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isTitleExpanded.toggle() }
                } label: {
                    Text(metadata.title)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isTitleExpanded ? 6 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.Shorts.title)
            }
            if isTitleExpanded, let published = metadata.publishedTimeText {
                Text(published)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .shortsInteractiveRegion()
    }

    // MARK: Action rail (bottom-right)

    private func actionRail(_ metadata: ShortMetadata) -> some View {
        VStack(spacing: 18) {
            railButton(
                symbol: metadata.likeStatus == .like ? AppSymbol.thumbsUpFill : AppSymbol.thumbsUp,
                label: metadata.likeCountText ?? "Like",
                accessibilityLabel: metadata.likeStatus == .like ? "Remove like" : "Like",
                id: AccessibilityID.Shorts.likeButton
            ) {
                requireSignIn { await feed.toggleLike(videoId: metadata.videoId) }
            }
            railButton(
                symbol: metadata.likeStatus == .dislike ? AppSymbol.thumbsDownFill : AppSymbol.thumbsDown,
                label: "Dislike",
                accessibilityLabel: metadata.likeStatus == .dislike ? "Remove dislike" : "Dislike",
                id: AccessibilityID.Shorts.dislikeButton
            ) {
                requireSignIn { await feed.toggleDislike(videoId: metadata.videoId) }
            }
            railButton(
                symbol: AppSymbol.commentsFill,
                label: metadata.commentCountText ?? "Comments",
                accessibilityLabel: "Comments",
                id: AccessibilityID.Shorts.commentsButton
            ) {
                activeSheet = .comments
            }
            railButton(
                symbol: AppSymbol.shareForward,
                label: "Share",
                accessibilityLabel: "Share",
                id: AccessibilityID.Shorts.shareButton
            ) {
                share(videoId: metadata.videoId)
            }
            railButton(
                symbol: AppSymbol.ellipsis,
                label: "",
                accessibilityLabel: "More",
                id: AccessibilityID.Shorts.moreButton
            ) {
                activeSheet = .more
            }
        }
        .shortsInteractiveRegion()
    }

    private func railButton(
        symbol: String,
        label: String,
        accessibilityLabel: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(height: 30)
                if !label.isEmpty {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .frame(minWidth: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(id)
    }

    // MARK: Progress bar

    /// Thin bar along the bottom edge; drag anywhere on it to scrub.
    private var progressBar: some View {
        GeometryReader { geo in
            let progress = scrubProgress ?? playbackProgress
            let isScrubbing = scrubProgress != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(Color.red)
                    .frame(width: max(0, geo.size.width * progress))
                if isScrubbing {
                    Circle().fill(Color.red)
                        .frame(width: 12, height: 12)
                        .offset(x: geo.size.width * progress - 6)
                }
            }
            .frame(height: isScrubbing ? 4 : 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubProgress = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                        seek(toFraction: fraction)
                        scrubProgress = nil
                    }
            )
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.1), value: scrubProgress != nil)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(playbackProgress * 100)) percent")
        .accessibilityIdentifier(AccessibilityID.Shorts.progressBar)
        .shortsInteractiveRegion()
    }

    private var playbackProgress: Double {
        #if os(iOS)
        guard vm.duration > 0 else { return 0 }
        return min(max(vm.currentTime / vm.duration, 0), 1)
        #else
        return 0
        #endif
    }

    private func seek(toFraction fraction: Double) {
        #if os(iOS)
        guard vm.duration > 0 else { return }
        vm.seekTo(fraction * vm.duration)
        #endif
    }

    // MARK: Actions

    func requireSignIn(_ action: @escaping @MainActor () async -> Void) {
        guard authService.isSignedIn else {
            showSignIn = true
            return
        }
        Task { await action() }
    }

    func openChannel(_ channelId: String?) {
        guard let channelId else { return }
        channelDestination = ChannelDestination(channelId: channelId)
    }

    /// Presents the system share sheet via UIKit so the swipe recognizers can be
    /// disabled until it's dismissed (a SwiftUI `ShareLink`'s presentation can't be observed).
    private func share(videoId: String) {
        #if os(iOS)
        guard let url = URL(string: "https://youtube.com/shorts/\(videoId)") else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in isSharing = false }
        }
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.bounds.midY, width: 1, height: 1)
        }
        isSharing = true
        top.present(controller, animated: true)
        #endif
    }

    #endif  // !os(tvOS)
}

// MARK: - Sheets

#if !os(tvOS)

/// Comments for one Short, as a resizable sheet (like the official app).
struct ShortsCommentsSheet: View {
    let videoId: String
    let commentCountText: String?
    @State private var controller: CommentsController

    init(videoId: String, commentCountText: String?, api: InnerTubeAPI) {
        self.videoId = videoId
        self.commentCountText = commentCountText
        _controller = State(initialValue: CommentsController(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if controller.isLoading && controller.comments.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if controller.comments.isEmpty {
                    Text("No comments available.", bundle: .module)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(controller.comments) { comment in
                        CommentRowView(comment: comment)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(commentCountText.map { "Comments \($0)" } ?? "Comments")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .accessibilityIdentifier(AccessibilityID.Shorts.commentsSheet)
        .onAppear { controller.load(videoId: videoId) }
    }
}

#endif
