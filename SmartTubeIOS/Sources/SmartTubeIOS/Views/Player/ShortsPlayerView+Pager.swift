import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Interactive paging
//
// Swiping drags the live Short and its neighbours together, like the official app:
// the previous/next Shorts are attached directly above/below and follow the finger.
//
// On iOS every page is a real video: `ShortsPlayerPool` keeps the next and previous
// Shorts loaded in their own web views, paused on their first frame, and each web
// view keeps its place in the hierarchy (moving one leaves it black, #279) — paging
// only changes offsets. A committed swipe slides the old Short off screen and the
// new one, already on screen with its first frame, starts playing.
//
// A page whose video has no frame yet (still loading, or failed) is covered by a
// *poster* — the Short's portrait thumbnail — which fades out once the frame is on
// screen, so the hand-off never flashes black. Neighbour pages also get a passive
// channel/title panel.

/// One page of the pager: a Short and its position relative to the live page.
struct ShortsPage: Identifiable {
    let video: Video
    /// -1 = previous, 0 = live, +1 = next.
    let position: Int
    var id: String { video.id }
}

/// Feel of the pager. One place for every paging threshold and animation.
enum ShortsPaging {
    /// Fraction of the page height a slow drag must cover to change page.
    static let commitFraction: CGFloat = 0.25
    /// A flick at least this fast (points/second) changes page regardless of distance.
    static let flickVelocity: CGFloat = 600
    /// Minimum drag for a flick to count (filters accidental micro-flicks).
    static let flickMinDistance: CGFloat = 12
    /// Drag resistance past the first/last Short.
    static let edgeResistance: CGFloat = 0.25
    static let commitDuration: TimeInterval = 0.32
    static let cancelAnimation = Animation.spring(duration: 0.3, bounce: 0.12)
    static let coverFadeAnimation = Animation.easeOut(duration: 0.18)
    /// The video shrinking above / growing back from the comments or description sheet.
    static let shrinkAnimation = Animation.spring(duration: 0.35, bounce: 0.1)
    /// Share of the screen a medium-detent sheet leaves free above it.
    static let shrunkSheetFraction: CGFloat = 0.5
    /// Caption cue distance from the bottom of the video, clear of the info panel.
    static let captionBottomInset: CGFloat = 150
    /// Extra trailing space so a caption cue never runs under the action rail.
    static let captionRailClearance: CGFloat = 52
}

extension ShortsPlayerView {

    /// The live page and its neighbours that exist.
    var pageWindow: [ShortsPage] {
        (-1...1).compactMap { position in
            let index = currentIndex + position
            return videos.indices.contains(index) ? ShortsPage(video: videos[index], position: position) : nil
        }
    }

    /// Height of one page (the player's own height, not the screen's — in the Shorts
    /// tab the player stops above the tab bar).
    var effectivePageHeight: CGFloat {
        if pageHeight > 0 { return pageHeight }
        #if os(iOS)
        return UIScreen.main.bounds.height
        #else
        return 1080
        #endif
    }

    /// A page's poster covers its web view until the video has a frame on screen.
    func isCovered(_ page: ShortsPage) -> Bool {
        #if os(iOS)
        !(pool.player(holding: page.video.id)?.hasFrame ?? false)
        #else
        page.position != 0
        #endif
    }

    #if os(iOS)
    /// Where a pool slot's web view sits: on its page, or parked off screen when it
    /// holds no Short of the current window.
    func slotOffset(for player: ShortsEmbedPlayerViewModel, pageHeight: CGFloat) -> CGFloat {
        guard let videoId = player.video?.id,
            let page = pageWindow.first(where: { $0.video.id == videoId })
        else { return pageHeight * 3 }
        return CGFloat(page.position) * pageHeight + slideOffset
    }
    #endif

    // MARK: Layers

    /// Thumbnails covering pages whose video has no frame yet, laid out in the
    /// video's coordinate space so they line up with the web views.
    func pagePosters(size: CGSize, videoHeight: CGFloat) -> some View {
        ForEach(pageWindow) { page in
            let isLive = page.position == 0
            let covered = isCovered(page)
            ShortsPosterView(video: page.video, width: size.width, videoHeight: videoHeight)
                .frame(width: size.width, height: size.height)
                .animation(ShortsPaging.coverFadeAnimation) { content in
                    content.opacity(covered ? 1 : 0)
                }
                .overlay {
                    if isLive && covered {
                        Color.clear.accessibilityIdentifier(AccessibilityID.Shorts.loadingCover)
                    }
                }
                .offset(y: CGFloat(page.position) * size.height + slideOffset)
                // While the video is shrunk above a sheet its neighbours would peek out.
                .opacity(!isLive && isVideoShrunk ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Passive channel/title panels for the neighbours, laid out like the live
    /// overlay's info panel so the hand-off when a page becomes live doesn't jump.
    @ViewBuilder
    var neighbourInfoPanels: some View {
        #if !os(tvOS)
        ForEach(pageWindow.filter { $0.position != 0 }) { page in
            ShortsPosterInfo(metadata: metadata(for: page.video))
                .offset(y: CGFloat(page.position) * effectivePageHeight + slideOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }

    private func metadata(for video: Video) -> ShortMetadata {
        feed.metadata[video.id]
            ?? ShortMetadata(
                videoId: video.id, title: video.title, channelTitle: video.channelTitle, channelId: video.channelId)
    }

    // MARK: Gesture

    /// Finger moved: the pages follow it, with resistance where there is no page.
    func handlePanChanged(_ translation: CGFloat) {
        guard !isTransitioning else { return }
        let hasTarget = translation < 0 ? currentIndex + 1 < videos.count : currentIndex > 0
        slideOffset = hasTarget ? translation : translation * ShortsPaging.edgeResistance
    }

    /// Finger lifted: change page if dragged far enough or flicked, else spring back.
    func handlePanEnded(translation: CGFloat, velocity: CGFloat) {
        guard !isTransitioning else { return }
        let toNext = translation < 0
        let farEnough = abs(translation) > effectivePageHeight * ShortsPaging.commitFraction
        let flicked =
            abs(velocity) > ShortsPaging.flickVelocity && abs(translation) > ShortsPaging.flickMinDistance
            && (velocity < 0) == toNext
        let target = ShortsNavigation.targetIndex(
            vertical: toNext ? -100 : 100, horizontal: 0, current: currentIndex, count: videos.count)
        guard farEnough || flicked, let target else {
            cancelPageDrag()
            if toNext, target == nil { loadMoreIfNeeded() }
            return
        }
        commitPage(direction: toNext ? -1 : 1, velocity: velocity) { goTo(target) }
    }

    func cancelPageDrag() {
        withAnimation(ShortsPaging.cancelAnimation) { slideOffset = 0 }
    }

    // MARK: Transition

    /// Slides the live page fully off screen in `direction` (-1 = up, +1 = down),
    /// continuing the finger's `velocity`, then runs `action` (switch Short) and puts
    /// the pager back at rest — without animation, so the neighbour that is now live
    /// stays exactly where it is.
    func commitPage(direction: CGFloat, velocity: CGFloat = 0, action: @escaping () -> Void) {
        isTransitioning = true
        let destination = direction * effectivePageHeight
        let remaining = destination - slideOffset
        // SwiftUI wants the initial velocity relative to the distance still to travel.
        let relativeVelocity = remaining == 0 ? 0 : min(max(Double(velocity / remaining), 0), 12)
        withAnimation(
            .interpolatingSpring(
                duration: ShortsPaging.commitDuration, bounce: 0, initialVelocity: relativeVelocity)
        ) {
            slideOffset = destination
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                action()
                slideOffset = 0
            }
            isTransitioning = false
        }
    }
}

// MARK: - Clipping

/// Clips only below the bottom edge. In the Shorts tab the page ends above the tab
/// bar, and nothing of the next page may show there; above and beside the page
/// (status bar, shrink animation) nothing is cut.
struct ShortsPageBottomClip: Shape {
    func path(in rect: CGRect) -> Path {
        let reach = max(rect.width, rect.height) * 4
        return Path(
            CGRect(
                x: rect.minX - reach, y: rect.minY - reach,
                width: rect.width + 2 * reach, height: rect.height + reach))
    }
}

// MARK: - Poster views

/// A Short's portrait thumbnail, framed like the live video.
struct ShortsPosterView: View {
    let video: Video
    let width: CGFloat
    let videoHeight: CGFloat

    var body: some View {
        ZStack {
            Color.black
            ThumbnailFillView(
                primaryURL: video.thumbnailURL,
                fallbackURLs: video.portraitThumbnailFallbackURLs(excluding: video.thumbnailURL),
                placeholder: .black,
                showsProgress: false
            )
            .frame(width: width, height: videoHeight)
            .clipped()
        }
    }
}

#if !os(tvOS)
/// Non-interactive version of the overlay's bottom gradient and info panel, for the
/// neighbour pages. Metrics mirror `officialStyleOverlay`/`infoPanel`.
struct ShortsPosterInfo: View {
    let metadata: ShortMetadata

    /// Room the live overlay's action rail takes on the right.
    private let railWidth: CGFloat = 64
    /// Height of the live overlay's progress bar row.
    private let progressBarHeight: CGFloat = 20

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AsyncImage(url: metadata.channelAvatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.white.opacity(0.25))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        Text(metadata.channelTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    if !metadata.title.isEmpty {
                        Text(metadata.title)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 12 + railWidth)
                .padding(.bottom, 10)
                Color.clear.frame(height: progressBarHeight)
            }
        }
    }
}
#endif
