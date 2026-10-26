#if !os(tvOS)
import SwiftUI
import SmartTubeIOSCore

// MARK: - PlayerProgressBarView
//
// Shared progress bar for both playback engines:
//   • PlayerControlsOverlay (direct/AVPlayer)
//   • TOSPlayerTransportOverlay (WKWebView/YouTube embed)
//
// The view is purely presentational + gesture-driven. The owning view model
// remains the source of truth for `isScrubbing`/`scrubTime`; this view only
// tracks a local `isDragging` flag so the tooltip appears on the first drag
// frame, before the parent's state has round-tripped.
struct PlayerProgressBarView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    var bufferedRanges: [ClosedRange<TimeInterval>] = []
    let isScrubbing: Bool
    let scrubTime: TimeInterval
    var chapters: [Chapter] = []
    var sponsorSegments: [SponsorSegment] = []
    var isLive: Bool = false
    var accessibilityIdentifier: String = "player.progressBar"
    var onBeginScrub: () -> Void = {}
    var onUpdateScrub: (TimeInterval) -> Void = { _ in }
    var onCommitScrub: () -> Void = {}
    var onSeek: (TimeInterval) -> Void = { _ in }

    @State private var isDragging = false

    private let hPad: CGFloat = 20

    private var isActiveScrub: Bool { isScrubbing || isDragging }
    private var displayTime: TimeInterval { isActiveScrub ? scrubTime : currentTime }

    var body: some View {
        GeometryReader { outerGeo in
            let trackW = max(outerGeo.size.width - hPad * 2, 1)
            let progress = fraction(for: displayTime)
            let thumbX = hPad + trackW * CGFloat(progress)

            VStack(spacing: 4) {
                tooltipRow(outerGeo: outerGeo, trackW: trackW, thumbX: thumbX)
                trackRow(trackW: trackW, thumbX: thumbX)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(scrubGesture(trackW: trackW))
        }
        .frame(height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipRow(outerGeo: GeometryProxy, trackW: CGFloat, thumbX: CGFloat) -> some View {
        GeometryReader { geo in
            if isActiveScrub, duration > 0 {
                let chapterAtScrub = chapters.last(where: { $0.startTime <= scrubTime })
                let labelW: CGFloat = chapterAtScrub != nil ? min(outerGeo.size.width * 0.5, 180) : 64
                let clampedX = min(max(thumbX, hPad + labelW / 2), outerGeo.size.width - hPad - labelW / 2)

                VStack(spacing: 2) {
                    if let chapter = chapterAtScrub {
                        Text(chapter.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(formatDuration(scrubTime))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: labelW)
                .position(x: clampedX, y: geo.size.height / 2)
            } else if isLive {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red.opacity(0.8), in: Capsule())
                    .position(x: hPad + 24, y: geo.size.height / 2)
            }
        }
        .frame(height: 28)
    }

    // MARK: - Track

    @ViewBuilder
    private func trackRow(trackW: CGFloat, thumbX: CGFloat) -> some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                    .padding(.horizontal, hPad)

                // Buffered ranges — subtle, behind the progress fill.
                Canvas { context, size in
                    for range in bufferedRanges {
                        let start = fraction(for: range.lowerBound)
                        let end = fraction(for: range.upperBound)
                        let width = trackW * CGFloat(max(end - start, 0))
                        guard width > 0 else { continue }
                        let rect = CGRect(
                            x: hPad + trackW * CGFloat(start),
                            y: size.height / 2 - 2,
                            width: width,
                            height: 4
                        )
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.28)))
                    }
                }
                .allowsHitTesting(false)

                // SponsorBlock markers.
                ForEach(sponsorSegments) { seg in
                    let start = fraction(for: seg.start)
                    let end = fraction(for: seg.end)
                    let width = trackW * CGFloat(max(end - start, 0))
                    Rectangle()
                        .fill(seg.category.color.opacity(0.8))
                        .frame(width: max(width, 2), height: 4)
                        .position(x: hPad + trackW * CGFloat(start) + width / 2, y: midY)
                }

                // Watched progress.
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: max(thumbX - hPad, 0), height: 4)
                    Spacer(minLength: 0)
                }
                .padding(.leading, hPad)

                // Chapter ticks. Kept tappable when not live; the parent's
                // high-priority drag gesture still wins for an actual scrub.
                ForEach(chapters) { chapter in
                    let x = hPad + trackW * CGFloat(fraction(for: chapter.startTime))
                    ZStack {
                        Color.clear
                            .frame(width: 24, height: 44)
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 2, height: 12)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isActiveScrub, !isLive else { return }
                        onSeek(chapter.startTime)
                    }
                    .position(x: x, y: midY)
                }

                if !isLive {
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .position(x: thumbX, y: midY)
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: - Gestures

    private func scrubGesture(trackW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLive, duration > 0 else { return }
                let raw = (value.location.x - hPad) / trackW
                let clamped = min(max(raw, 0), 1)
                if !isDragging {
                    isDragging = true
                    onBeginScrub()
                }
                onUpdateScrub(Double(clamped) * duration)
            }
            .onEnded { _ in
                guard !isLive, duration > 0 else {
                    isDragging = false
                    return
                }
                isDragging = false
                onCommitScrub()
            }
    }

    // MARK: - Helpers

    private func fraction(for time: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    private var accessibilityValue: String {
        if isLive { return "Live" }
        return "\(formatDuration(displayTime)) of \(formatDuration(duration))"
    }
}
#endif
