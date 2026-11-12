import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

private let menuLog = Logger(subsystem: appSubsystem, category: "ShortsPlayer")

// MARK: - ⋯ menu actions, captions, toast, shrunk video

extension ShortsPlayerView {

    #if !os(tvOS)

    func handleMenuAction(_ action: ShortsMenuAction) {
        guard let video = currentVideo else {
            activeSheet = nil
            return
        }
        switch action {
        case .description:
            activeSheet = .description
        case .saveToPlaylist:
            activeSheet = .saveToPlaylist
        case .clearScreen:
            activeSheet = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isTitleExpanded = false
                isScreenCleared = true
            }
            showToast(String(localized: "Tap to show controls", bundle: .module))
        case .notInterested:
            activeSheet = nil
            sendFeedback(videoId: video.id, iconType: "NOT_INTERESTED")
            showToast(String(localized: "You'll see fewer Shorts like this", bundle: .module))
            swipe(toNext: true)
        case .dontRecommendChannel:
            activeSheet = nil
            guard let metadata = currentMetadata, let channelId = metadata.channelId else { return }
            sendFeedback(videoId: video.id, iconType: "BLOCK_CHANNEL")
            store.settings.blockedChannels[channelId] = metadata.channelTitle
            feed.hideChannel(channelId, after: currentIndex)
            showToast(String(localized: "This channel won't be recommended", bundle: .module))
            swipe(toNext: true)
        case .report:
            activeSheet = nil
            // Reporting needs YouTube's own flow (reasons, sign-in, appeal).
            if let url = URL(string: "https://www.youtube.com/shorts/\(video.id)") { openURL(url) }
        }
    }

    func handleSavedToPlaylist(_ result: Result<PlaylistInfo, Error>) {
        switch result {
        case .success(let playlist):
            showToast(String(localized: "Saved to \(playlist.title)", bundle: .module))
        case .failure(let error):
            showToast(error.localizedDescription)
        }
    }

    private func sendFeedback(videoId: String, iconType: String) {
        Task {
            do {
                try await api.sendFeedbackForVideo(videoId: videoId, iconType: iconType)
            } catch {
                menuLog.notice(
                    "Shorts \(iconType, privacy: .public) feedback failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }
    }

    @ViewBuilder
    var toast: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.top, 64)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier(AccessibilityID.Shorts.toast)
                .task(id: toastMessage) {
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { self.toastMessage = nil }
                }
        }
    }

    #endif

    // MARK: Captions

    #if os(iOS)
    func applyCaptions() {
        captions.apply(
            videoId: currentVideo?.id,
            enabled: store.settings.shortsCaptions,
            preferredLanguage: store.settings.preferredCaptionLanguage,
            currentTime: vm.currentTime)
    }
    #endif

    /// The current caption cue, at the bottom of the live video above the info panel.
    @ViewBuilder
    func captionLayer(layout: ShortsVideoLayout) -> some View {
        #if os(iOS)
        if let text = captions.cueText {
            VStack {
                Spacer()
                let controlsHidden = isScreenCleared || isVideoShrunk
                CaptionCueView(text: text)
                    // Keep clear of the action rail while it's showing.
                    .padding(.trailing, controlsHidden ? 0 : ShortsPaging.captionRailClearance)
                    .padding(.bottom, controlsHidden ? 24 : ShortsPaging.captionBottomInset)
            }
            .frame(height: layout.box.height)
            .offset(y: layout.boxCenterOffset + slideOffset)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: isScreenCleared)
        }
        #endif
    }

    // MARK: Shrunk video

    /// Space above the video while shrunk: the top safe area.
    var shrunkTopInset: CGFloat { max(playerFrame.minY, 12) }

    /// Scale that fits a video area of `height` between the top safe area and a
    /// medium-detent sheet.
    func shrunkScale(height: CGFloat) -> CGFloat {
        guard height > 0 else { return 1 }
        #if os(iOS)
        let screenHeight = UIScreen.main.bounds.height
        #else
        let screenHeight = height
        #endif
        let available = screenHeight * ShortsPaging.shrunkSheetFraction - shrunkTopInset - 8
        return min(1, max(0.25, available / height))
    }
}
