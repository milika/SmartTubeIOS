import SwiftUI
import SmartTubeIOSCore

// MARK: - PlayerView tvOS extensions
//
// All tvOS-specific logic for PlayerView: the control navigation model,
// the Siri Remote key handlers (tvNextControl / tvActivateControl),
// and the custom tvOS progress bar layout.
// Body modifiers (.focusable, .onMoveCommand, etc.) and stored properties
// (@FocusState, @State highlightedControl) remain in PlayerView.swift because
// Swift does not allow stored properties in extensions.

#if os(tvOS)

// MARK: - ConditionalMoveCommand

/// Conditionally applies `.onMoveCommand`. When `enabled = false` the modifier is
/// completely absent from the view tree (not just a no-op closure), which allows
/// D-pad events to fall through to SwiftUI's native focus engine so it can move
/// focus between buttons inside an overlay's VStack.
///
/// `.onMoveCommand(perform: nil)` is NOT equivalent — it still registers a
/// modifier node in the responder chain and can prevent the focus engine from
/// receiving the event.
struct ConditionalMoveCommand: ViewModifier {
    let enabled: Bool
    let action: (MoveCommandDirection) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onMoveCommand(perform: action)
        } else {
            content   // modifier completely absent — D-pad reaches native focus engine
        }
    }
}

extension PlayerView {

    // MARK: - MoreMenuRow

    /// Identifies each focusable row in the more menu overlay.
    /// Navigation is native SwiftUI focus via the `.focused($moreMenuFocusedRow, equals:)`
    /// binding on each row; initial focus is set to `.speed` when the menu opens
    /// (PlayerView+Lifecycle). The case value drives the row's focus highlight.
    enum MoreMenuRow: Hashable {
        case speed, quality, like, dislike, sleepTimer, audioOnly, queueShuffle, captions,
             audioTrack, description, comments, statsForNerds, cancel
    }

    // MARK: - TVPlayerControl

    /// Represents each focusable control button in the tvOS overlay.
    /// Navigation between controls is handled entirely in software via
    /// `tvNextControl(from:direction:)` rather than SwiftUI's native focus
    /// engine, giving full control over the d-pad routing logic.
    enum TVPlayerControl: Equatable {
        case back, channel, more                             // top row
        case seekBack, playPause, seekForward                // centre row
        case prevVideo, prevChapter, nextChapter, nextVideo  // bottom row

        var isTopRow: Bool {
            switch self { case .back, .channel, .more: true; default: false }
        }
        var isCenterRow: Bool {
            switch self { case .seekBack, .playPause, .seekForward: true; default: false }
        }
    }

    // MARK: - Overlay state

    /// True when any picker or menu overlay is open.
    /// When true, the player yields focus to the overlay so its buttons
    /// are reachable by the Siri Remote.
    var isAnyOverlayVisible: Bool {
        showMoreMenu || showQualityPicker || showSpeedPicker || showSleepTimerPicker || showCaptionPicker || showAudioTrackPicker
            || showDescriptionSheet || showCommentsSheet
    }

    /// True while a SponsorBlock skip toast is visible.
    /// Kept separate from `isAnyOverlayVisible` so the `onChange(of: isAnyOverlayVisible)`
    /// handler's `vm.cancelControlsHide()` call is not triggered by the transient toast.
    var isSkipToastActive: Bool {
        vm.currentToastSegment != nil
    }

    // MARK: - Controls navigation

    /// Returns the next control to highlight when the user presses a d-pad direction.
    func tvNextControl(from current: TVPlayerControl, direction: MoveCommandDirection) -> TVPlayerControl {
        switch direction {
        case .left:
            switch current {
            // top row
            case .more:        return .channel
            case .channel:     return .back
            // center row
            case .playPause:   return .seekBack
            case .seekForward: return .playPause
            // bottom row
            case .prevChapter: return .prevVideo
            case .nextChapter: return .prevChapter
            case .nextVideo:   return vm.chapters.isEmpty ? .prevVideo : .nextChapter
            default: return current
            }
        case .right:
            switch current {
            // top row
            case .back:        return .channel
            case .channel:     return .more
            // center row
            case .seekBack:    return .playPause
            case .playPause:   return .seekForward
            // bottom row
            case .prevVideo:   return vm.chapters.isEmpty ? .nextVideo : .prevChapter
            case .prevChapter: return .nextChapter
            case .nextChapter: return .nextVideo
            default: return current
            }
        case .up:
            if current.isCenterRow { return .more }   // center → top row
            if !current.isCenterRow && !current.isTopRow {
                // bottom row → center row (map by position)
                switch current {
                case .prevVideo, .prevChapter: return .seekBack
                default:                       return .seekForward
                }
            }
            return current  // already at top
        case .down:
            if current.isTopRow { return .playPause }  // top row → center row
            if current.isCenterRow {                   // center row → bottom row
                switch current {
                case .seekBack: return vm.chapters.isEmpty ? .prevVideo : .prevChapter
                default:        return vm.chapters.isEmpty ? .nextVideo : .nextChapter
                }
            }
            return current  // already at bottom
        @unknown default: return current
        }
    }

    /// Executes the action for the currently highlighted control.
    func tvActivateControl(_ control: TVPlayerControl) {
        let playerLog = CrashlyticsLogger(category: "Player")
        playerLog.notice("[tv] tvActivateControl(\(String(describing: control)))")
        switch control {
        case .back:        vm.stop(); withAnimation(.none) { dismiss() }
        case .channel:
            let channelId = vm.playerInfo?.video.channelId ?? video.channelId
            if let cid = channelId, !cid.isEmpty { channelDestination = ChannelDestination(channelId: cid) }
        case .more:
            playerLog.notice("[tv] .more activated — setting showMoreMenu=true")
            showMoreMenu = true; highlightedControl = nil
        case .seekBack:    vm.seekRelative(seconds: -Double(store.settings.seekBackSeconds))
        case .playPause:   vm.togglePlayPause()
        case .seekForward: vm.seekRelative(seconds: Double(store.settings.seekForwardSeconds))
        case .prevVideo:   if vm.hasPrevious { vm.playPrevious() }
        case .prevChapter: if vm.hasPreviousChapter { vm.skipToPreviousChapter() }
        case .nextChapter: if vm.hasNextChapter { vm.skipToNextChapter() }
        case .nextVideo:   if vm.hasNext { vm.playNext() }
        }
    }

}

extension PlayerControlsOverlay {

    // MARK: - tvOS progress bar

    /// Custom progress bar for tvOS: larger thumb, wider padding, bigger time labels.
    /// The iOS variant (`iosProgressBar`) lives in PlayerView+ControlElements.swift.
    var tvProgressBar: some View {
        VStack(spacing: 6) {
            // Scrub time tooltip
            GeometryReader { geo in
                if vm.isScrubbing && vm.duration > 0 {
                    let hPad: CGFloat = 40
                    let trackW = geo.size.width - hPad * 2
                    let fraction = CGFloat(vm.scrubTime / vm.duration)
                    let thumbX = hPad + trackW * fraction
                    let chapterAtScrub = vm.chapters.last(where: { $0.startTime <= vm.scrubTime })
                    let labelW: CGFloat = chapterAtScrub != nil ? min(geo.size.width * 0.45, 220) : 90
                    let clampedX = min(max(thumbX, hPad + labelW / 2), geo.size.width - hPad - labelW / 2)

                    VStack(spacing: 2) {
                        if let chapter = chapterAtScrub {
                            Text(chapter.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(formatDuration(vm.scrubTime))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: labelW)
                    .position(x: clampedX, y: geo.size.height / 2)
                }
            }
            .frame(height: 36)

            // Track row
            GeometryReader { geo in
                let hPad: CGFloat = 40
                let trackW = geo.size.width - hPad * 2
                let time = vm.isScrubbing ? vm.scrubTime : vm.currentTime
                let progress = vm.duration > 0 ? CGFloat(time / vm.duration) : 0
                let thumbX = hPad + trackW * progress

                ZStack {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 6)
                        .padding(.horizontal, hPad)

                    // Progress fill
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: max(thumbX - hPad, 0), height: 6)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, hPad)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .position(x: thumbX, y: geo.size.height / 2)
                }
                .overlay(sponsorBlockMarkers)
                .overlay(chapterMarkers)
            }
            .frame(height: 36)

            // Time labels
            HStack {
                Text(formatDuration(vm.currentTime))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.leading, 40)
                Spacer()
                Text(formatDuration(vm.duration))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.trailing, 40)
            }
        }
    }
}
#endif
