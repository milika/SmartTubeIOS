import AVFoundation
import SmartTubeIOSCore
import SwiftUI

// MARK: - Self-contained auxiliary views used by PlayerView
//
// Extracted from PlayerView.swift to keep that file under 1 000 lines.

// MARK: - StatsForNerdsOverlay

struct StatsForNerdsOverlay: View {
    let snapshot: StatsForNerdsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row(L10n.string("Video ID"), snapshot.videoId)
            row(
                L10n.string("Resolution"),
                snapshot.fps > 0
                    ? "\(snapshot.displayResolution) @ \(snapshot.fps) fps"
                    : snapshot.displayResolution)
            if !snapshot.pendingQualityLabel.isEmpty {
                identifiedRow(
                    L10n.string("Selected"), snapshot.pendingQualityLabel,
                    valueId: "stats.selectedQuality")
            }
            row(L10n.string("Codec"), snapshot.codec)
            row(L10n.string("Nominal Bitrate"), snapshot.nominalBitrate)
            row(L10n.string("Connection Speed"), snapshot.observedBitrate)
            row(L10n.string("Dropped Frames"), "\(snapshot.droppedFrames)")
            row(L10n.string("Stalls"), "\(snapshot.stalls)")
            Divider().background(.white.opacity(0.2)).padding(.vertical, 2)
            row(L10n.string("TTP (low-q)"), snapshot.timeToPlayMs > 0 ? "\(snapshot.timeToPlayMs) ms" : "—")
            row(
                L10n.string("TTP (hi-q)"), snapshot.timeToHighQualityMs > 0 ? "\(snapshot.timeToHighQualityMs) ms" : "—"
            )
            row(L10n.string("Stream Type"), snapshot.streamType.isEmpty ? "—" : snapshot.streamType)
            row(L10n.string("Cache"), snapshot.cacheStatus.isEmpty ? "—" : snapshot.cacheStatus)
            smallRow(L10n.string("Stream URL"), snapshot.streamURL.isEmpty ? "—" : snapshot.streamURL)
            Divider().background(.white.opacity(0.2)).padding(.vertical, 2)
            row(L10n.string("Report ID"), snapshot.reportID)
            Text("Two-finger tap to dismiss  ·  Quote Report ID when sending diagnostics", bundle: L10n.bundle)
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(.caption2, design: .monospaced))
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func smallRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(.caption2, design: .monospaced))
    }

    /// Like `row` but applies an accessibility identifier to the value text,
    /// allowing XCUITest to locate it directly by identifier.
    private func identifiedRow(_ key: String, _ value: String, valueId: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white)
                .accessibilityIdentifier(valueId)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

// MARK: - RelatedVideosView

struct RelatedVideosView: View {
    let videos: [Video]
    let onSelect: (Video) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(videos) { video in
                    VideoCardView(video: video, compact: true)
                        .padding(.horizontal)
                        .onTapGesture { onSelect(video) }
                }
            }
        }
    }
}

// MARK: - CommentRowView

struct CommentRowView: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: comment.authorAvatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.secondary.opacity(0.3))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(comment.publishedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(timestampLinkedAttributedString(comment.text))
                    .font(.callout)
                if !comment.likeCount.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup")
                            .font(.caption2)
                        Text(comment.likeCount)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timestampLinkedAttributedString(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for (range, seconds) in findTimestamps(in: text) {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].link = URL(string: "smarttube://seek/\(Int(seconds))")
        }
        return attributed
    }
}

// MARK: - EndCardOverlay

/// Positions YouTube end-screen cards absolutely within the player bounds.
/// Cards are shown only during their `startMs…endMs` window and dismissed when
/// the controls overlay is visible (consistent with official YouTube behaviour).
#if !os(tvOS)
struct EndCardOverlay: View {
    let cards: [EndCard]
    let currentTime: TimeInterval
    let onSelect: (EndCard) -> Void

    private var visibleCards: [EndCard] {
        let ms = Int(currentTime * 1000)
        return cards.filter { $0.style == .video && $0.videoId != nil && ms >= $0.startMs && ms <= $0.endMs }
    }

    var body: some View {
        // Self-sizing via an internal GeometryReader avoids passing geo.size from the
        // outer player GeometryReader. Passing geo.size directly and then setting an
        // explicit .frame(width: geo.size.width, height: geo.size.height) here created
        // an AnimatableFrameAttribute that fed back into the outer GR during animations,
        // causing SIGSEGV/SIGBUS crashes at AttributeGraph recursion level 10.
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(visibleCards) { card in
                    let cardWidth = card.width / 100 * proxy.size.width
                    let cardHeight = cardWidth / max(card.aspectRatio, 0.1)
                    let x = card.left / 100 * proxy.size.width
                    let y = card.top / 100 * proxy.size.height
                    EndCardButton(card: card, width: cardWidth, height: cardHeight, onSelect: onSelect)
                        .offset(x: x, y: y)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeOut(duration: 0.2), value: visibleCards.count)
                }
            }
            .allowsHitTesting(!visibleCards.isEmpty)
        }
    }
}

struct EndCardButton: View {
    let card: EndCard
    let width: CGFloat
    let height: CGFloat
    let onSelect: (EndCard) -> Void

    var body: some View {
        Button {
            onSelect(card)
        } label: {
            ZStack(alignment: .bottom) {
                AsyncImage(url: card.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.4)
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                if !card.title.isEmpty {
                    Text(card.title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.65))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("End card: \(card.title)", bundle: L10n.bundle))
    }
}
#endif

// MARK: - AppSettings.VideoGravityMode → AVLayerVideoGravity mapping

extension AppSettings.VideoGravityMode {
    var avGravity: AVLayerVideoGravity {
        self == .fill ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - AirPlayRoutePickerView

#if canImport(UIKit)
import UIKit
import AVKit

/// Wraps `AVRoutePickerView` (the iOS AirPlay button) in a SwiftUI-compatible view.
struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor.systemBlue
        // Set the identifier directly on the UIKit view so XCUITest can find it.
        // The SwiftUI `.accessibilityIdentifier()` modifier applies to the hosting
        // wrapper view, not to AVRoutePickerView itself.
        picker.accessibilityIdentifier = "player.airPlayButton"
        picker.isAccessibilityElement = true
        picker.accessibilityTraits = [.button]
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
