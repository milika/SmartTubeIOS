import SwiftUI
import SmartTubeIOSCore
import os
#if canImport(UIKit)
import UIKit
#endif

private let menuLog = CrashlyticsLogger(category: "PlayerMenu")

// Measures the natural height of moreMenuItems so the sheet hugs its content
// instead of always expanding to moreMenuMaxHeight.
private struct MoreMenuContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - PlayerView overlay sheets
//
// Pure-SwiftUI overlays rendered inside the player's ZStack so no UIKit
// sheet presentation fires onDisappear and tears down playback.
//
// Includes:
//   • moreMenuOverlay      — all top-bar actions + share/download
//   • descriptionOverlay   — scrollable video description
//   • commentsOverlay      — video comments list
//   • loadComments()       — async comment fetching
//   • descriptionAttributedString(_:) — URL linkification helper

extension PlayerView {

    // MARK: - Overlay stack

    /// All picker / sheet overlays rendered inside the player ZStack.
    /// Consolidating them here caps the 8-branch ModifiedContent type tree in a single
    /// compiled function, reducing __swift5_typeref size in the binary.
    @ViewBuilder var overlayStack: some View {
        if showMoreMenu {
            moreMenuOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showMoreMenu)
        }
        if showSpeedPicker {
            speedPickerOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showSpeedPicker)
        }
        if showQualityPicker {
            qualityPickerOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showQualityPicker)
        }
        if showCaptionPicker {
            captionPickerOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showCaptionPicker)
        }
        if showAudioTrackPicker {
            audioTrackPickerOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showAudioTrackPicker)
        }
        if showSleepTimerPicker {
            sleepTimerPickerOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showSleepTimerPicker)
        }
        if showDescriptionSheet {
            descriptionOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showDescriptionSheet)
        }
        if showCommentsSheet {
            commentsOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showCommentsSheet)
        }
    }

    // MARK: - More menu overlay

    /// Pure-SwiftUI bottom sheet combining all top-bar controls + Share/Download.
    /// Rendered inside the player's ZStack so no UIKit sheet presentation
    /// fires onDisappear and teardowns the action sheet mid-animation.
    var moreMenuOverlay: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        menuLog.notice("[moreMenu] rendering — video=\(currentVideo.id) availableFormats=\(vm.availableFormats.count) isSignedIn=\(authService.isSignedIn)")
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    menuLog.notice("[moreMenu] background tap — dismissing")
                    showMoreMenu = false
                }

            // ScrollView capped at moreMenuMaxHeight to avoid GeometryReader/containerRelativeFrame
            // feedback loops that crash SwiftUI's AttributeGraph (SIGSEGV/SIGBUS recursion).
            // Previously this used ViewThatFits with duplicate moreMenuItems references; that pattern
            // causes AttributeGraph EXC_BAD_ACCESS when SwiftUI evaluates both alternatives and the
            // shared @ViewBuilder identity produces a graph cycle. Using a single ScrollView path
            // is safe because .frame(maxHeight:) already caps the height appropriately.
            ScrollView {
                moreMenuItems
                    // Measure the VStack's natural height one pass before the
                    // containing frame is applied, so the sheet hugs its content.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MoreMenuContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .accessibilityIdentifier("player.moreMenu.scrollView")
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onPreferenceChange(MoreMenuContentHeightKey.self) { moreMenuContentHeight = $0 }
            // Height = natural content height capped at moreMenuMaxHeight.
            // Falls back to moreMenuMaxHeight on the first render (before the
            // preference arrives), then snaps to the correct size on the next pass.
            .frame(maxWidth: moreMenuPortraitWidth, maxHeight: moreMenuContentHeight > 0 ? min(moreMenuContentHeight, moreMenuMaxHeight) : moreMenuMaxHeight)
            #if os(tvOS)
            // Native SwiftUI focus handles D-pad navigation via the .focused() bindings
            // on each row button. onMoveCommand was removed because it caused a double-step
            // bug: both onMoveCommand and the native focus engine responded to the same
            // D-pad event, advancing focus twice per press.
            .onExitCommand {
                menuLog.notice("[moreMenu] onExitCommand fired — dismissing via Menu button")
                showMoreMenu = false
            }
            .onAppear {
                menuLog.notice("[moreMenu] overlay appeared — native tvOS focus via .focused() bindings")
            }
            .onDisappear {
                menuLog.notice("[moreMenu] overlay disappeared")
            }
            #endif
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.horizontal, moreMenuAdditionalHorizontalPadding)
            .safeAreaPadding(.bottom)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        #if os(tvOS)
        .focusScope(moreMenuNamespace)
        #endif
    }

    @ViewBuilder private var moreMenuItems: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        VStack(spacing: 0) {
            // Centered title header
            VStack(spacing: 2) {
                Text(currentVideo.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !currentVideo.channelTitle.isEmpty {
                    Text(currentVideo.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            #if os(tvOS)
            moreMenuSpeedRow
            moreMenuQualityRow
            #endif
            moreMenuLikeDislikeRow
            moreMenuShareRow
            #if os(tvOS)
            moreMenuSleepTimerRow
            moreMenuAudioOnlyRow
            #endif
            moreMenuQueueShuffleRow
            moreMenuDownloadRow
            moreMenuCaptionsRow
            moreMenuAudioTrackRow
            moreMenuDescriptionRow
            moreMenuCommentsRow
            moreMenuStatsForNerdsRow
            moreMenuCancelRow
        }
        .frame(maxWidth: .infinity)
        .font(.subheadline)
    }

    private var moreMenuMaxHeight: CGFloat {
        #if os(iOS)
        verticalSizeClass == .compact ? 320 : 440
        #else
        520
        #endif
    }

    private var moreMenuAdditionalHorizontalPadding: CGFloat {
        #if os(iOS)
        vm.isLandscape ? 36 : 0
        #else
        0
        #endif
    }

    var moreMenuPortraitWidth: CGFloat {
        #if os(iOS)
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.8
        #else
        .infinity
        #endif
    }

    // MARK: - Description overlay

    var descriptionOverlay: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        let description = currentVideo.description ?? ""
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showDescriptionSheet = false }

            VStack(spacing: 0) {
                HStack {
                    Button { showDescriptionSheet = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Description")
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 4)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(currentVideo.title)
                            .font(.headline)
                        if !currentVideo.channelTitle.isEmpty {
                            Text(currentVideo.channelTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !description.isEmpty {
                            Text(descriptionAttributedString(description))
                                .font(.body)
                        } else {
                            Text("No description available.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .frame(maxHeight: 400)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            #if os(tvOS)
            .focusScope(descriptionOverlayNamespace)
            .onExitCommand { showDescriptionSheet = false }
            #endif
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }

    func descriptionAttributedString(_ string: String) -> AttributedString {
        var attributed = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let nsString = string as NSString
        let matches = detector.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            guard let range = Range(match.range, in: string),
                  let url = match.url,
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].link = url
        }
        // Timestamp linkification: add smarttube://seek/<seconds> links for MM:SS / HH:MM:SS spans.
        // Only applied where NSDataDetector has not already set a link (URLs take precedence).
        for (range, seconds) in findTimestamps(in: string) {
            guard let attrRange = Range(range, in: attributed) else { continue }
            if attributed[attrRange].link == nil {
                attributed[attrRange].link = URL(string: "smarttube://seek/\(Int(seconds))")
            }
        }
        return attributed
    }

    // MARK: - Comments overlay

    var commentsOverlay: some View {
        #if os(tvOS)
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false },
            focusNamespace: commentsOverlayNamespace
        )
        #else
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false }
        )
        #endif
    }

    // MARK: - Comments loading

    func loadComments() {
        let videoId = (vm.playerInfo?.video ?? video).id
        vm.comments.load(videoId: videoId)
    }

    // MARK: - More menu rows
    //
    // Each row is a @ViewBuilder var so its type tree is a separate compiled function,
    // reducing moreMenuOverlay from one ~10.5 KB symbol to many ~1 KB symbols.

    @ViewBuilder private var moreMenuSpeedRow: some View {
        Button {
            menuLog.notice("[moreMenu] Speed row tapped — closing moreMenu, opening speedPicker")
            showMoreMenu = false
            showSpeedPicker = true
        } label: {
            HStack {
                Label("Playback Speed", systemImage: "speedometer")
                Spacer()
                Text(store.settings.playbackSpeed == 1.0 ? "Normal"
                     : "\(store.settings.playbackSpeed, specifier: "%.2g")×")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.speedRow")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .speed ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .speed)
        .prefersDefaultFocus(in: moreMenuNamespace)
        #endif
        Divider()
    }

    #if os(tvOS)
    @ViewBuilder private var moreMenuQualityRow: some View {
        if !vm.availableFormats.isEmpty {
            Button {
                menuLog.notice("[moreMenu] Quality row tapped — closing moreMenu, opening qualityPicker")
                showMoreMenu = false
                showQualityPicker = true
            } label: {
                HStack {
                    Label("Quality", systemImage: "film.stack")
                    Spacer()
                    Text(vm.selectedFormat?.qualityLabel
                         ?? (vm.pendingQualityLabel.isEmpty ? "Auto" : vm.pendingQualityLabel))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("player.moreMenu.qualityRow")
            .background(moreMenuFocusedRow == .quality ? Color.gray.opacity(0.35) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .focused($moreMenuFocusedRow, equals: .quality)
            Divider()
        }
    }
    #endif

    private var shouldShowAudioTrackInMoreMenu: Bool {
        #if os(tvOS)
        vm.availableAudioTracks.count > 1
        #else
        vm.availableAudioTracks.count > 1 && !vm.controlsVisible
        #endif
    }

    @ViewBuilder private var moreMenuLikeDislikeRow: some View {
        if authService.isSignedIn {
            HStack(spacing: 0) {
                Button {
                    vm.like()
                    showMoreMenu = false
                } label: {
                    Label(
                        vm.likeStatus == .like ? "Liked" : "Like",
                        systemImage: vm.likeStatus == .like
                            ? "\(AppSymbol.thumbsUp).fill" : AppSymbol.thumbsUp
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(vm.likeStatus == .like ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.moreMenu.likeRow")
                #if os(tvOS)
                .background(moreMenuFocusedRow == .like ? Color.gray.opacity(0.35) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($moreMenuFocusedRow, equals: .like)
                #endif
                Divider().frame(height: 44)
                Button {
                    vm.dislike()
                    showMoreMenu = false
                } label: {
                    Label(
                        vm.likeStatus == .dislike ? "Disliked" : "Dislike",
                        systemImage: vm.likeStatus == .dislike
                            ? "\(AppSymbol.thumbsDown).fill" : AppSymbol.thumbsDown
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(vm.likeStatus == .dislike ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.moreMenu.dislikeRow")
                #if os(tvOS)
                .background(moreMenuFocusedRow == .dislike ? Color.gray.opacity(0.35) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($moreMenuFocusedRow, equals: .dislike)
                #endif
            }
            Divider()
        }
    }

    @ViewBuilder private var moreMenuShareRow: some View {
        #if os(iOS)
        Button {
            showMoreMenu = false
            if let url = URL(string: "https://www.youtube.com/watch?v=\((vm.playerInfo?.video ?? video).id)") {
                presentShareSheet(url: url)
            }
        } label: {
            Label("Share", systemImage: AppSymbol.share)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        Divider()
        #endif
    }

    @ViewBuilder private var moreMenuSleepTimerRow: some View {
        Button {
            menuLog.notice("[moreMenu] Sleep Timer row tapped — closing moreMenu, opening sleepTimerPicker")
            showMoreMenu = false
            showSleepTimerPicker = true
        } label: {
            HStack {
                Label("Sleep Timer", systemImage: "moon.zzz")
                Spacer()
                if let mins = vm.sleepTimerMinutes {
                    Text("\(mins) min")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Off")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.sleepTimerRow")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .sleepTimer ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .sleepTimer)
        #endif
        Divider()
    }

    @ViewBuilder private var moreMenuAudioOnlyRow: some View {
        Button {
            menuLog.notice("[moreMenu] Audio-Only row tapped — toggling audioOnlyMode: \(store.settings.audioOnlyMode) → \(!store.settings.audioOnlyMode)")
            vm.toggleAudioOnlyLive()
            store.settings.audioOnlyMode = vm.isAudioOnlyMode
            showMoreMenu = false
        } label: {
            HStack {
                Label(
                    store.settings.audioOnlyMode
                        ? String(localized: "Audio-Only (On)", bundle: .module)
                        : String(localized: "Audio-Only", bundle: .module),
                    systemImage: AppSymbol.audioOnly
                )
                Spacer()
                if store.settings.audioOnlyMode {
                    Image(systemName: AppSymbol.checkmark)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.audioOnlyRow")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .audioOnly ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .audioOnly)
        #endif
        Divider()
    }

    @ViewBuilder private var moreMenuQueueShuffleRow: some View {
        if (vm.playerInfo?.video ?? video).playlistId == CurrentQueueStore.playlistID {
            Button {
                menuLog.notice("[moreMenu] Queue Shuffle row tapped — toggling queueShuffleEnabled: \(store.settings.queueShuffleEnabled) → \(!store.settings.queueShuffleEnabled)")
                store.settings.queueShuffleEnabled.toggle()
                showMoreMenu = false
            } label: {
                HStack {
                    Label(
                        store.settings.queueShuffleEnabled
                            ? String(localized: "Shuffle Queue (On)", bundle: .module)
                            : String(localized: "Shuffle Queue", bundle: .module),
                        systemImage: "shuffle"
                    )
                    Spacer()
                    if store.settings.queueShuffleEnabled {
                        Image(systemName: AppSymbol.checkmark)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("player.moreMenu.queueShuffleRow")
            #if os(tvOS)
            .background(moreMenuFocusedRow == .queueShuffle ? Color.gray.opacity(0.35) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .focused($moreMenuFocusedRow, equals: .queueShuffle)
            #endif
            Divider()
        }
    }

    @ViewBuilder private var moreMenuDownloadRow: some View {
        #if !os(tvOS)
        Button {
            showMoreMenu = false
            downloadService.download(video: vm.playerInfo?.video ?? video)
        } label: {
            Group {
                if downloadService.state.isActive {
                    Label("Downloading…", systemImage: AppSymbol.download)
                } else {
                    Label("Download to Gallery", systemImage: AppSymbol.download)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(downloadService.state.isActive)
        .accessibilityIdentifier("player.moreMenu.downloadButton")
        Divider()
        #endif
    }

    @ViewBuilder private var moreMenuCaptionsRow: some View {
        if !vm.availableCaptions.isEmpty {
            Button {
                showMoreMenu = false
                showCaptionPicker = true
            } label: {
                HStack {
                    Label("Captions", systemImage: "captions.bubble")
                    Spacer()
                    Text(vm.selectedCaption.map {
                        $0.isAutoGenerated ? "\($0.name) (auto)" : $0.name
                    } ?? "Off")
                    .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("player.moreMenu.captionsRow")
            #if os(tvOS)
            .background(moreMenuFocusedRow == .captions ? Color.gray.opacity(0.35) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .focused($moreMenuFocusedRow, equals: .captions)
            #endif
            Divider()
        }
    }

    @ViewBuilder private var moreMenuAudioTrackRow: some View {
        if shouldShowAudioTrackInMoreMenu {
            Button {
                showMoreMenu = false
                showAudioTrackPicker = true
            } label: {
                HStack {
                    Label("Audio Track", systemImage: "waveform")
                    Spacer()
                    Text(vm.selectedAudioTrack.map {
                        $0.isOriginal ? "\($0.name) (Original)" : $0.name
                    } ?? "Auto")
                    .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("player.moreMenu.audioTrackRow")
            #if os(tvOS)
            .background(moreMenuFocusedRow == .audioTrack ? Color.gray.opacity(0.35) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .focused($moreMenuFocusedRow, equals: .audioTrack)
            #endif
            Divider()
        }
    }

    @ViewBuilder private var moreMenuDescriptionRow: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        if !(currentVideo.description ?? "").isEmpty {
            Button {
                showMoreMenu = false
                showDescriptionSheet = true
            } label: {
                Label("Description", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("player.moreMenu.descriptionRow")
            #if os(tvOS)
            .background(moreMenuFocusedRow == .description ? Color.gray.opacity(0.35) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .focused($moreMenuFocusedRow, equals: .description)
            #endif
            Divider()
        }
    }

    @ViewBuilder private var moreMenuCommentsRow: some View {
        Button {
            showMoreMenu = false
            showCommentsSheet = true
            loadComments()
        } label: {
            Label("Comments", systemImage: "bubble.left.and.bubble.right")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.commentsRow")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .comments ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .comments)
        #endif
        Divider()
    }

    @ViewBuilder private var moreMenuStatsForNerdsRow: some View {
        Button {
            vm.toggleStatsForNerds()
            showMoreMenu = false
        } label: {
            HStack {
                Label("Stats for Nerds", systemImage: "chart.bar.xaxis")
                Spacer()
                if vm.statsForNerdsVisible {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.statsForNerds")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .statsForNerds ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .statsForNerds)
        #endif
        Divider()
    }

    @ViewBuilder private var moreMenuCancelRow: some View {
        Button { showMoreMenu = false } label: {
            Text("Cancel")
                .frame(maxWidth: .infinity)
                .padding()
                .fontWeight(.semibold)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("player.moreMenu.cancel")
        #if os(tvOS)
        .background(moreMenuFocusedRow == .cancel ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .cancel)
        #endif
    }
}
