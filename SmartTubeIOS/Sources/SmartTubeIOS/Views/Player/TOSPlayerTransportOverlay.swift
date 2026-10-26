#if !os(tvOS)
import SwiftUI
import SmartTubeIOSCore

// MARK: - TOSPlayerTransportOverlay
//
// Native transport chrome for the TOS WKWebView player. Composed from the
// shared PlayerControls subviews so the direct player and TOS stay visually
// identical. The embedded YouTube chrome is hidden by TOSPlayerChromeJS; this
// view is the only visible UI in normal (non-ad) playback.
//
// The overlay is always mounted; `controlsVisible` only fades/hit-tests the
// chrome. Picker sheets are rendered outside that fade so an auto-hide cannot
// dismiss an open picker.
struct TOSPlayerTransportOverlay<MoreMenu: View>: View {
    let vm: TOSPlayerViewModel
    let video: Video
    let safeAreaInsets: EdgeInsets
    let controlsVisible: Bool
    let isLandscapeLocked: Binding<Bool>
    /// The existing more menu, built by TOSPlayerView so it can reuse its
    /// comments/chapters/like/sleep actions without moving that state here.
    /// A generic builder keeps the Menu's identity stable across the 250 ms
    /// tick-driven re-renders (an AnyView would recreate it and may close an
    /// open native menu).
    @ViewBuilder let moreMenu: () -> MoreMenu
    let onBack: (() -> Void)?
    let onInteraction: () -> Void

    @Environment(SettingsStore.self) private var store

    @State private var showQualityPicker = false
    @State private var showSpeedPicker = false
    /// Owned by TOSPlayerView so the more menu's Captions / Audio Track rows
    /// can open the same pickers as the quick-access pills.
    @Binding var showCaptionsPicker: Bool
    @Binding var showAudioTrackPicker: Bool
    @State private var showSleepTimerPicker = false
    /// Set by the CC pill's long-press so the button's release action doesn't
    /// also toggle captions when the user only wanted the language picker.
    @State private var suppressCaptionTap = false

    private var chromeVisible: Bool {
        controlsVisible && !vm.isAd
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                centreTransport
                Spacer(minLength: 0)
                bottomBar
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)

            pickerOverlays
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            PlayerIconButton(
                systemName: AppSymbol.chevronLeft,
                accessibilityIdentifier: "tosPlayer.backButton",
                accessibilityLabel: "Back",
                iconSize: 22
            ) {
                onInteraction()
                onBack?()
            }
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(video.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            moreMenu()
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        // The GeometryReader that hosts this view is already constrained to
        // the safe area on iOS, so a small fixed inset is correct here.
        8
        #else
        // macOS draws the window titlebar/toolbar above the content view; the
        // reported safe-area inset is the only reliable clearance.
        max(safeAreaInsets.top, 16)
        #endif
    }

    // MARK: - Centre transport

    private var centreTransport: some View {
        HStack(spacing: 40) {
            PlayerIconButton(
                systemName: "gobackward.\(store.settings.seekBackSeconds)",
                accessibilityIdentifier: "tosPlayer.seekBackButton",
                accessibilityLabel: "Seek back",
                iconSize: 30,
                padding: 12,
                backgroundOpacity: 0
            ) {
                onInteraction()
                vm.seekRelative(-Double(store.settings.seekBackSeconds))
            }

            PlayerIconButton(
                systemName: playPauseSymbol,
                accessibilityIdentifier: "tosPlayer.playPauseButton",
                accessibilityLabel: vm.isPlaying ? "Pause" : "Play",
                iconSize: 42,
                padding: 12,
                backgroundOpacity: 0
            ) {
                onInteraction()
                vm.togglePlayPause()
            }

            PlayerIconButton(
                systemName: "goforward.\(store.settings.seekForwardSeconds)",
                accessibilityIdentifier: "tosPlayer.seekForwardButton",
                accessibilityLabel: "Seek forward",
                iconSize: 30,
                padding: 12,
                backgroundOpacity: 0
            ) {
                onInteraction()
                vm.seekRelative(Double(store.settings.seekForwardSeconds))
            }
        }
    }

    private var playPauseSymbol: String {
        if vm.playerState == .ended { return "arrow.counterclockwise" }
        return vm.isPlaying ? "pause.fill" : "play.fill"
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let chapter = vm.currentChapter {
                Text(chapter.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PlayerProgressBarView(
                currentTime: vm.currentTime,
                duration: vm.duration,
                bufferedRanges: vm.bufferedRanges,
                isScrubbing: vm.isScrubbing,
                scrubTime: vm.scrubTime,
                chapters: vm.chapters,
                sponsorSegments: vm.sponsorSegments,
                // Live broadcasts are scrubable: the DVR window is the timeline.
                // The LIVE state is shown by the pill next to the time labels.
                isLive: false,
                accessibilityIdentifier: "tosPlayer.progressBar",
                onBeginScrub: {
                    onInteraction()
                    vm.beginScrubbing()
                },
                onUpdateScrub: { vm.updateScrub(to: $0) },
                onCommitScrub: { vm.commitScrub() },
                onSeek: { vm.seekTo($0) }
            )

            quickAccessRow

            HStack(spacing: 8) {
                // Playlist-only: hidden entirely unless this video came from the
                // Current Queue (a playlist). Inside a queue they navigate it
                // (both disabled for a one-item queue).
                if vm.isInPlaylist {
                    PlayerIconButton(
                        systemName: AppSymbol.previousTrack,
                        accessibilityIdentifier: "tosPlayer.previousButton",
                        accessibilityLabel: "Previous video",
                        iconSize: 20,
                        isEnabled: vm.canPlayPreviousVideo
                    ) {
                        onInteraction()
                        vm.playPrevious()
                    }
                }

                // Chapter jump — always present, disabled when the video has no
                // chapters or the playhead is at the relevant boundary.
                PlayerIconButton(
                    systemName: AppSymbol.previousChapter,
                    accessibilityIdentifier: "tosPlayer.previousChapterButton",
                    accessibilityLabel: "Previous chapter",
                    iconSize: 20,
                    isEnabled: vm.hasPreviousChapter
                ) {
                    onInteraction()
                    vm.skipToPreviousChapter()
                }

                if vm.isLive {
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .accessibilityIdentifier("tosPlayer.liveLabel")
                }
                // Always show elapsed / total. For a live broadcast the total is
                // the DVR edge, i.e. how long the stream has been running.
                Text(formatDuration(vm.currentTime))
                    .accessibilityIdentifier("tosPlayer.currentTimeLabel")
                Text("/")
                    .foregroundStyle(.white.opacity(0.5))
                Text(formatDuration(vm.duration))
                    .accessibilityIdentifier("tosPlayer.durationLabel")

                Spacer()

                PlayerIconButton(
                    systemName: AppSymbol.nextChapter,
                    accessibilityIdentifier: "tosPlayer.nextChapterButton",
                    accessibilityLabel: "Next chapter",
                    iconSize: 20,
                    isEnabled: vm.hasNextChapter
                ) {
                    onInteraction()
                    vm.skipToNextChapter()
                }

                if vm.isInPlaylist {
                    PlayerIconButton(
                        systemName: AppSymbol.nextTrack,
                        accessibilityIdentifier: "tosPlayer.nextButton",
                        accessibilityLabel: "Next video",
                        iconSize: 20,
                        isEnabled: vm.canPlayNextVideo
                    ) {
                        onInteraction()
                        vm.playNext()
                    }
                }

                #if os(iOS)
                PlayerIconButton(
                    systemName: isLandscapeLocked.wrappedValue ? "lock.rotation" : "lock.rotation.open",
                    accessibilityIdentifier: "tosPlayer.landscapeLockButton",
                    accessibilityLabel: "Landscape lock"
                ) {
                    onInteraction()
                    isLandscapeLocked.wrappedValue.toggle()
                }
                #endif
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private var quickAccessRow: some View {
        // Horizontal scroll: with speed + quality + captions + audio + sleep all
        // present the row can exceed the available width, so let the user scroll
        // it rather than truncating ("Normal" → "No…", "Deutsch" → "De…").
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PlayerQuickAccessPill(
                    systemImage: "speedometer",
                    label: speedLabel,
                    accessibilityIdentifier: "tosPlayer.speedButton"
                ) {
                    onInteraction()
                    showSpeedPicker = true
                }

                if vm.hasQualityOptions {
                    PlayerQuickAccessPill(
                        systemImage: "film.stack",
                        label: vm.qualityLabel,
                        accessibilityIdentifier: "tosPlayer.qualityButton"
                    ) {
                        onInteraction()
                        showQualityPicker = true
                    }
                }

                // Always visible: the pill toggles captions when tracks are known,
                // and its picker explains the empty state when they are not (so
                // the control's presence does not depend on the embed API).
                PlayerQuickAccessPill(
                    systemImage: vm.selectedCaption == nil ? "captions.bubble" : "captions.bubble.fill",
                    label: vm.captionsLabel,
                    accessibilityIdentifier: "tosPlayer.captionsButton"
                ) {
                    onInteraction()
                    if suppressCaptionTap {
                        suppressCaptionTap = false
                        return
                    }
                    vm.toggleCaptions()
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        onInteraction()
                        suppressCaptionTap = true
                        showCaptionsPicker = true
                    }
                )

                // Always visible, like the CC pill: alternate audio tracks are an
                // embed capability, so the control is present even when the list
                // is empty and the picker explains the empty state.
                PlayerQuickAccessPill(
                    systemImage: "waveform",
                    label: vm.audioTrackLabel,
                    accessibilityIdentifier: "tosPlayer.audioTrackButton"
                ) {
                    onInteraction()
                    showAudioTrackPicker = true
                }

                PlayerQuickAccessPill(
                    systemImage: "moon.zzz",
                    label: sleepTimerLabel,
                    accessibilityIdentifier: "tosPlayer.sleepTimerButton"
                ) {
                    onInteraction()
                    showSleepTimerPicker = true
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var speedLabel: String {
        store.settings.playbackSpeed == 1.0
            ? "Normal"
            : String(format: "%.2g×", store.settings.playbackSpeed)
    }

    private var sleepTimerLabel: String {
        guard let minutes = vm.sleepTimerMinutes else { return "Sleep" }
        return "\(minutes)m"
    }

    // MARK: - Pickers

    @ViewBuilder
    private var pickerOverlays: some View {
        if showQualityPicker {
            PlayerPickerSheet(
                title: "Quality",
                options: vm.qualityPickerOptions(),
                accessibilityIdentifier: "tosPlayer.qualityPicker",
                onSelect: { option in
                    showQualityPicker = false
                    onInteraction()
                    Task { @MainActor in
                        if option.id == "auto" {
                            store.settings.preferredQuality = .auto
                            await vm.selectQuality("auto")
                        } else {
                            if let quality = vm.availableQualities.first(where: { $0.id == option.id }),
                                let mapped = AppSettings.VideoQuality.from(height: quality.height)
                            {
                                store.settings.preferredQuality = mapped
                            }
                            await vm.selectQuality(option.id)
                        }
                    }
                },
                onDismiss: {
                    showQualityPicker = false
                    onInteraction()
                }
            )
        }

        if showSpeedPicker {
            PlayerPickerSheet(
                title: "Playback Speed",
                options: AppSettings.availableSpeeds.map { speed in
                    PlayerPickerOption(
                        id: String(speed),
                        title: speed == 1.0 ? "Normal (1×)" : String(format: "%.2g×", speed),
                        isSelected: abs(store.settings.playbackSpeed - speed) < 0.01
                    )
                },
                accessibilityIdentifier: "tosPlayer.speedPicker",
                onSelect: { option in
                    showSpeedPicker = false
                    onInteraction()
                    guard let speed = Double(option.id) else { return }
                    store.settings.playbackSpeed = speed
                    vm.setPlaybackRate(speed)
                },
                onDismiss: {
                    showSpeedPicker = false
                    onInteraction()
                }
            )
        }

        if showCaptionsPicker {
            PlayerPickerSheet(
                title: "Captions",
                options: vm.captionPickerOptions(),
                accessibilityIdentifier: "tosPlayer.captionPicker",
                onSelect: { option in
                    showCaptionsPicker = false
                    onInteraction()
                    if option.id == "captions-refresh" {
                        Task { @MainActor in
                            await vm.fetchNativeCaptionTracks(force: true)
                            showCaptionsPicker = true
                        }
                        return
                    }
                    if option.id == "off" {
                        store.settings.preferredCaptionLanguage = nil
                        vm.selectCaption(nil)
                    } else if let track = vm.captionTrack(withOptionID: option.id) {
                        store.settings.preferredCaptionLanguage = track.languageCode
                        vm.selectCaption(track)
                    }
                },
                onDismiss: {
                    showCaptionsPicker = false
                    onInteraction()
                }
            )
        }

        if showAudioTrackPicker {
            PlayerPickerSheet(
                title: "Audio Track",
                options: vm.audioTrackPickerOptions(),
                accessibilityIdentifier: "tosPlayer.audioTrackPicker",
                onSelect: { option in
                    showAudioTrackPicker = false
                    onInteraction()
                    if option.id == "audio-refresh" {
                        Task { @MainActor in
                            await vm.refreshMediaOptions()
                            showAudioTrackPicker = true
                        }
                        return
                    }
                    guard let index = audioIndex(from: option.id) else { return }
                    store.settings.preferredAudioLanguage =
                        vm.availableAudioTracks.first(where: { $0.index == index })?.languageCode
                    Task { @MainActor in await vm.selectAudioTrack(index: index) }
                },
                onDismiss: {
                    showAudioTrackPicker = false
                    onInteraction()
                }
            )
        }

        if showSleepTimerPicker {
            PlayerPickerSheet(
                title: "Sleep Timer",
                options: sleepTimerOptions,
                accessibilityIdentifier: "tosPlayer.sleepTimerPicker",
                onSelect: { option in
                    showSleepTimerPicker = false
                    onInteraction()
                    vm.setSleepTimer(minutes: Int(option.id))
                },
                onDismiss: {
                    showSleepTimerPicker = false
                    onInteraction()
                }
            )
        }
    }

    private var sleepTimerOptions: [PlayerPickerOption] {
        var options: [PlayerPickerOption] = [
            PlayerPickerOption(
                id: "off",
                title: "Off",
                isSelected: vm.sleepTimerMinutes == nil
            )
        ]
        options.append(
            contentsOf: PlaybackViewModel.sleepTimerOptions.map { minutes in
                PlayerPickerOption(
                    id: String(minutes),
                    title: "\(minutes) min",
                    isSelected: vm.sleepTimerMinutes == minutes
                )
            })
        return options
    }

    private func audioIndex(from optionID: String) -> Int? {
        Int(optionID.replacingOccurrences(of: "audio-", with: ""))
    }
}
#endif
