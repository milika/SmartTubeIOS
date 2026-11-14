import AuthenticationServices
import SmartTubeIOSCore
import SwiftUI

// MARK: - SettingsView
//
// App preferences.  Mirrors the Android settings presenters
// (PlayerData, MainUIData, SponsorBlockData, DeArrowData, AccountsData).

public struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @State private var showSignIn = false
    @State private var reportSent = false
    #if os(tvOS)
    @State private var showGithubQR = false
    #endif
    /// #126: whether the current visit to this screen has already passed the PIN
    /// check. Reset to `false` on `.onDisappear` (see body) so leaving and coming back
    /// to Settings (e.g. switching tabs) re-locks it — a parental-control PIN that
    /// only had to be entered once per app launch wouldn't stop a kid who's already
    /// seen the tab switch away and back.
    @State private var isUnlocked = false
    @State private var parentalControlsSheetMode: ParentalControlsMode?

    public init() {}

    public var body: some View {
        Group {
            if let pinHash = store.settings.settingsPINHash, !isUnlocked {
                SettingsPINLockView(expectedHash: pinHash) { isUnlocked = true }
            } else {
                settingsForm
            }
        }
        .onDisappear {
            if store.settings.settingsPINHash != nil { isUnlocked = false }
        }
    }

    private var settingsForm: some View {
        Form {
            accountSection
            playerSection
            generalSection
            uiSection
            sponsorBlockSection
            deArrowSection
            parentalControlsSection
            #if os(macOS)
            experimentalSection
            #endif
            aboutSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        // Hide the blank navigation bar on iOS and tvOS — a visible nav bar on tvOS
        // conflicts with the TabView tab bar scroll-hide animation (issue #102 / gh-34).
        // .navigationBar placement is unavailable on macOS.
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        #if os(tvOS)
        .sheet(isPresented: $showGithubQR) {
            GitHubQRView()
        }
        #endif
        .sheet(item: $parentalControlsSheetMode) { mode in
            ParentalControlsSheet(mode: mode)
        }
    }

    // MARK: - Parental Controls

    private var parentalControlsSection: some View {
        Section {
            if store.settings.settingsPINHash == nil {
                Button(L10n.string("Set PIN")) { parentalControlsSheetMode = .set }
                    .accessibilityIdentifier("settings.setPINButton")
            } else {
                Button(L10n.string("Change PIN")) { parentalControlsSheetMode = .change }
                    .accessibilityIdentifier("settings.changePINButton")
                Button(L10n.string("Remove PIN"), role: .destructive) { parentalControlsSheetMode = .remove }
                    .accessibilityIdentifier("settings.removePINButton")
            }
        } header: {
            Text("Parental Controls", bundle: L10n.bundle)
        } footer: {
            Text(
                "When a PIN is set, it must be entered every time this Settings screen is opened.", bundle: L10n.bundle)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(L10n.string("Account")) {
            if auth.isSignedIn {
                HStack {
                    #if os(tvOS)
                    let avatarSize: CGFloat = 64
                    #else
                    let avatarSize: CGFloat = 40
                    #endif
                    AsyncImage(url: auth.accountAvatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure, .empty:
                            Circle().fill(Color.secondary.opacity(0.3))
                                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                        @unknown default:
                            Circle().fill(Color.secondary.opacity(0.3))
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    Text(auth.accountName ?? L10n.string("Unknown"))
                }
                NavigationLink {
                    ChannelSwitcherView()
                } label: {
                    LabeledContent(L10n.string("Channel"), value: auth.activeChannel?.name ?? "")
                }
                .accessibilityIdentifier("settings.channelLink")
                Button(L10n.string("Sign Out"), role: .destructive) { auth.signOut() }
            } else {
                Button(L10n.string("Sign in with Google")) { showSignIn = true }
                    .accessibilityIdentifier("settings.signInButton")
                    .sheet(isPresented: $showSignIn) { SignInView() }
            }
        }
    }

    // MARK: - Player

    private var playerSection: some View {
        @Bindable var store = store
        return Section(L10n.string("Player")) {
            Picker(L10n.string("Playback Speed"), selection: $store.settings.playbackSpeed) {
                ForEach(AppSettings.availableSpeeds, id: \.self) { s in
                    Text(s == 1.0 ? "Normal" : "\(s, specifier: "%.2g")×", bundle: L10n.bundle).tag(s)
                }
            }

            #if !os(iOS)
            Picker(L10n.string("Default Quality"), selection: $store.settings.preferredQuality) {
                ForEach(AppSettings.VideoQuality.allCases, id: \.self) { q in
                    Text(q.displayName).tag(q)
                }
            }
            .accessibilityIdentifier("settings.preferredQualityPicker")

            Picker(L10n.string("Preferred Audio Language"), selection: $store.settings.preferredAudioLanguage) {
                Text("System Default", bundle: L10n.bundle).tag(nil as String?)
                Divider()
                Text("English", bundle: L10n.bundle).tag("en" as String?)
                Text("Spanish", bundle: L10n.bundle).tag("es" as String?)
                Text("French", bundle: L10n.bundle).tag("fr" as String?)
                Text("German", bundle: L10n.bundle).tag("de" as String?)
                Text("Japanese", bundle: L10n.bundle).tag("ja" as String?)
                Text("Korean", bundle: L10n.bundle).tag("ko" as String?)
                Text("Portuguese (Brazil)", bundle: L10n.bundle).tag("pt-BR" as String?)
                Text("Chinese (Simplified)", bundle: L10n.bundle).tag("zh-Hans" as String?)
                Divider()
                Text("Original Track Only", bundle: L10n.bundle).tag("original" as String?)
            }
            .accessibilityIdentifier("settings.preferredAudioLanguageRow")
            #endif

            #if os(tvOS)
            Picker(L10n.string("Seek Back"), selection: $store.settings.seekBackSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s", bundle: L10n.bundle).tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekBackRow")
            Picker(L10n.string("Seek Forward"), selection: $store.settings.seekForwardSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s", bundle: L10n.bundle).tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekForwardRow")
            #elseif os(macOS)
            Stepper(
                L10n.string("Seek Back: \(store.settings.seekBackSeconds) s"),
                value: $store.settings.seekBackSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekBackRow")
            Stepper(
                L10n.string("Seek Forward: \(store.settings.seekForwardSeconds) s"),
                value: $store.settings.seekForwardSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekForwardRow")
            #endif

            #if !os(iOS)
            Picker(L10n.string("Hide Controls After"), selection: $store.settings.controlsHideTimeout) {
                Text("2s", bundle: L10n.bundle).tag(2)
                Text("3s", bundle: L10n.bundle).tag(3)
                Text("4s", bundle: L10n.bundle).tag(4)
                Text("5s", bundle: L10n.bundle).tag(5)
                Text("8s", bundle: L10n.bundle).tag(8)
                Text("10s", bundle: L10n.bundle).tag(10)
            }

            Picker(L10n.string("Video Fit"), selection: $store.settings.videoGravityMode) {
                Text("Fit (letterbox)", bundle: L10n.bundle).tag(AppSettings.VideoGravityMode.fit)
                Text("Fill (crop)", bundle: L10n.bundle).tag(AppSettings.VideoGravityMode.fill)
            }
            #endif

            Toggle(L10n.string("Loop Video"), isOn: $store.settings.loopEnabled)
            Toggle(L10n.string("Shuffle"), isOn: $store.settings.shuffleEnabled)

            Toggle(L10n.string("Autoplay next video"), isOn: $store.settings.autoplayEnabled)
            Toggle(L10n.string("Background Playback"), isOn: $store.settings.backgroundPlaybackEnabled)
            #if !os(iOS)
            Toggle(L10n.string("Prefer H.264 Codec"), isOn: $store.settings.preferH264)
                .accessibilityIdentifier("settings.preferH264Toggle")
            #endif
        }
    }

    // MARK: - General

    private var generalSection: some View {
        @Bindable var store = store
        return Section {
            Picker(L10n.string("Watch History"), selection: $store.settings.historyState) {
                Text("Enabled", bundle: L10n.bundle).tag(AppSettings.HistoryState.enabled)
                Text("Disabled", bundle: L10n.bundle).tag(AppSettings.HistoryState.disabled)
            }
            if !LocalWatchHistoryStore.shared.entries.isEmpty {
                Button(L10n.string("Clear Watch History on This Device"), role: .destructive) {
                    LocalWatchHistoryStore.shared.clear()
                }
                .accessibilityIdentifier("settings.clearLocalHistoryButton")
            }
            Toggle(L10n.string("Sync to iCloud"), isOn: $store.settings.iCloudSyncEnabled)
                .accessibilityIdentifier("settings.iCloudSyncToggle")
        } header: {
            Text("General", bundle: L10n.bundle)
        } footer: {
            Text(
                "Watch history is saved on this device. SmartTube also tries to report watches to your YouTube account, but YouTube may not always record them.",
                bundle: L10n.bundle
            )
        }
    }

    // MARK: - UI

    private enum ThumbnailStyle: Hashable {
        case standard, highResolution, compact
    }

    /// UI-only view over the two independent `compactThumbnails` / `highResThumbnails` flags.
    private var thumbnailStyle: Binding<ThumbnailStyle> {
        Binding(
            get: {
                if store.settings.compactThumbnails { return .compact }
                return store.settings.highResThumbnails ? .highResolution : .standard
            },
            set: { style in
                store.settings.compactThumbnails = style == .compact
                store.settings.highResThumbnails = style == .highResolution
            }
        )
    }

    private var uiSection: some View {
        @Bindable var store = store
        return Section(L10n.string("Interface")) {
            Picker(L10n.string("Theme"), selection: $store.settings.themeName) {
                ForEach(AppSettings.ThemeName.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .accessibilityIdentifier("settings.themeRow")
            Picker(L10n.string("Accent Color"), selection: $store.settings.accentColor) {
                ForEach(AppSettings.AccentColorChoice.allCases, id: \.self) { choice in
                    Label {
                        Text(choice.displayName)
                    } icon: {
                        choice.swatch
                    }
                    .tag(choice)
                }
            }
            .accessibilityIdentifier("settings.accentColorPicker")
            Picker(L10n.string("Thumbnails"), selection: thumbnailStyle) {
                Text("Standard", bundle: L10n.bundle).tag(ThumbnailStyle.standard)
                Text("High Resolution", bundle: L10n.bundle).tag(ThumbnailStyle.highResolution)
                Text("Compact", bundle: L10n.bundle).tag(ThumbnailStyle.compact)
            }
            .accessibilityIdentifier("settings.thumbnailStylePicker")
            #if !os(tvOS)
            Picker(L10n.string("Columns (Portrait)"), selection: $store.settings.gridColumnsPortrait) {
                ForEach(AppSettings.availableGridColumnCounts, id: \.self) {
                    Text("\($0)", bundle: L10n.bundle).tag($0)
                }
            }
            .disabled(store.settings.compactThumbnails)
            .accessibilityIdentifier("settings.gridColumnsPortraitPicker")
            Picker(L10n.string("Columns (Landscape)"), selection: $store.settings.gridColumnsLandscape) {
                ForEach(AppSettings.availableGridColumnCounts, id: \.self) {
                    Text("\($0)", bundle: L10n.bundle).tag($0)
                }
            }
            .disabled(store.settings.compactThumbnails)
            .accessibilityIdentifier("settings.gridColumnsLandscapePicker")
            #endif
            Toggle(L10n.string("Hide Shorts"), isOn: $store.settings.hideShorts)
                .accessibilityIdentifier("settings.hideShortsToggle")
            Toggle(L10n.string("Hide Live Shorts"), isOn: $store.settings.hideLiveShorts)
                .accessibilityIdentifier("settings.hideLiveShortsToggle")
            Toggle(L10n.string("Hide Video Premieres"), isOn: $store.settings.hideVideoPremieres)
                .accessibilityIdentifier("settings.hideVideoPremieresToggle")
            Toggle(L10n.string("Per-Device Recommendations"), isOn: $store.settings.perDeviceRecommendationsEnabled)
                .accessibilityIdentifier("settings.perDeviceRecommendationsToggle")
            Toggle(L10n.string("Hide Watched Videos"), isOn: $store.settings.hideWatchedVideos)
                .accessibilityIdentifier("settings.hideWatchedVideosToggle")
            if store.settings.hideWatchedVideos {
                #if os(tvOS)
                // tvOS has no Stepper.
                Picker(L10n.string("Watched threshold"), selection: $store.settings.hideWatchedThreshold) {
                    ForEach(Array(stride(from: 50, through: 100, by: 5)), id: \.self) { percent in
                        Text("\(percent)%", bundle: L10n.bundle).tag(Double(percent) / 100)
                    }
                }
                .accessibilityIdentifier("settings.hideWatchedThresholdStepper")
                #else
                Stepper(
                    L10n.string("Watched threshold: \(Int(store.settings.hideWatchedThreshold * 100))%"),
                    value: $store.settings.hideWatchedThreshold, in: 0.5...1.0, step: 0.05
                )
                .accessibilityIdentifier("settings.hideWatchedThresholdStepper")
                #endif
            }
            #if os(iOS)
            if #available(iOS 26.0, *) {
                Toggle(L10n.string("Disable Liquid Glass"), isOn: $store.settings.disableLiquidGlass)
                    .accessibilityIdentifier("settings.disableLiquidGlassToggle")
            }
            #endif
            NavigationLink(L10n.string("Visible Sections")) {
                SectionsSettingsView()
                    .environment(store)
            }
            .accessibilityIdentifier("settings.visibleSectionsLink")
        }
    }

    // MARK: - SponsorBlock

    private var sponsorBlockSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(L10n.string("Enable SponsorBlock"), isOn: $store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier("settings.sponsorBlockToggle")

            if store.settings.sponsorBlockEnabled {
                ForEach(SponsorSegment.Category.allCases, id: \.self) { cat in
                    HStack {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 10, height: 10)
                        Picker(
                            cat.displayName,
                            selection: Binding(
                                get: { store.settings.sponsorBlockActions[cat] ?? .nothing },
                                set: { store.settings.sponsorBlockActions[cat] = $0 }
                            )
                        ) {
                            Text("Skip", bundle: L10n.bundle).tag(AppSettings.SponsorBlockAction.skip)
                            Text("Show Toast", bundle: L10n.bundle).tag(AppSettings.SponsorBlockAction.showToast)
                            Text("Nothing", bundle: L10n.bundle).tag(AppSettings.SponsorBlockAction.nothing)
                        }
                        .accessibilityIdentifier("settings.sponsorBlock.\(cat.rawValue)")
                    }
                }

                // Minimum segment duration
                Picker(L10n.string("Min. Segment Length"), selection: $store.settings.sponsorBlockMinSegmentDuration) {
                    Text("Off", bundle: L10n.bundle).tag(0.0)
                    Text("1s", bundle: L10n.bundle).tag(1.0)
                    Text("2s", bundle: L10n.bundle).tag(2.0)
                    Text("5s", bundle: L10n.bundle).tag(5.0)
                    Text("10s", bundle: L10n.bundle).tag(10.0)
                }

                // Excluded channels
                NavigationLink(L10n.string("Excluded Channels (\(store.settings.sponsorBlockExcludedChannels.count))"))
                {
                    SponsorBlockExcludedChannelsView()
                }
                .accessibilityIdentifier("settings.sponsorBlockExcludedChannels")
            }
        } header: {
            Text("SponsorBlock", bundle: L10n.bundle)
        } footer: {
            Text(
                "Skip \u{2014} auto-skips. Show Toast \u{2014} shows a skip button. Nothing \u{2014} plays through.",
                bundle: L10n.bundle)
        }
    }

    // MARK: - DeArrow

    private var deArrowSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(L10n.string("Enable DeArrow"), isOn: $store.settings.deArrowEnabled)
        } header: {
            Text("DeArrow", bundle: L10n.bundle)
        } footer: {
            Text("Replace clickbait titles and thumbnails with community-sourced alternatives.", bundle: L10n.bundle)
        }
    }

    // MARK: - Experimental (macOS)

    #if os(macOS)
    private var experimentalSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(L10n.string("IFrame Player (TOS-compliant, shows ads)"), isOn: $store.settings.useTOSPlayerOnMac)
                .accessibilityIdentifier("settings.useTOSPlayerOnMacToggle")
        } header: {
            Text("Experimental", bundle: L10n.bundle)
        } footer: {
            Text(
                "Uses YouTube's official embedded player instead of the direct stream pipeline. Quality selection is unavailable. Ads will play. Useful for videos that refuse to play via the standard path.",
                bundle: L10n.bundle
            )
        }
    }
    #endif

    // MARK: - About

    private var aboutSection: some View {
        @Bindable var store = store
        return Section {
            LabeledContent(L10n.string("Version"), value: appVersion)
            Toggle(L10n.string("Disable Analytics & Crash Reporting"), isOn: $store.settings.disableAnalytics)
                .accessibilityIdentifier("settings.disableAnalyticsToggle")
            Text("Restart the app for this to take effect.", bundle: L10n.bundle)
                .font(.caption)
                .foregroundStyle(.secondary)
            #if os(tvOS)
            Button {
                showGithubQR = true
            } label: {
                Label(L10n.string("View on GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #else
            Link(destination: URL(string: "https://github.com/milika/SmartTubeIOS")!) {
                Label(L10n.string("View on GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #endif
            Button {
                CrashlyticsLogger.sendDiagnosticReport()
                reportSent = true
            } label: {
                if reportSent {
                    Label(L10n.string("Report Sent"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(L10n.string("Send Diagnostic Report"), systemImage: "ladybug")
                }
            }
            .disabled(reportSent || store.settings.disableAnalytics)
            .accessibilityIdentifier("settings.sendDiagnosticReportButton")
            Button(L10n.string("Reset All Settings"), role: .destructive) { store.reset() }
                .accessibilityIdentifier("settings.resetAllButton")
        } header: {
            Text("About", bundle: L10n.bundle)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - GitHubQRView (tvOS)

#if os(tvOS)
private struct GitHubQRView: View {
    @Environment(\.dismiss) private var dismiss

    private let githubURL = "https://github.com/milika/SmartTubeIOS"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)

                    Text("SmartTube on GitHub", bundle: L10n.bundle)
                        .font(.largeTitle).fontWeight(.bold)

                    Text("Scan the QR code with your phone to view the project on GitHub.", bundle: L10n.bundle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                QRCodeView(content: githubURL)
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(githubURL)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Label(L10n.string("Close"), systemImage: "xmark")
                    .font(.headline)
            }
            .padding(40)
        }
    }
}
#endif

// MARK: - SectionsSettingsView

/// Lets the user configure which sections appear in the sidebar / tab bar.
/// Mirrors Android's `MainUIData` section ordering/enabling UI.
struct SectionsSettingsView: View {
    @Environment(SettingsStore.self) private var store

    private let allSections = BrowseSection.allSections

    /// #156: visible sections in the user's own order (drag-to-reorder below), each
    /// resolved back to its `BrowseSection` for a title/icon.
    private var visibleSections: [BrowseSection] {
        store.settings.enabledSections.compactMap { type in allSections.first { $0.type == type } }
    }

    private var hiddenSections: [BrowseSection] {
        allSections.filter { !store.settings.enabledSections.contains($0.type) }
    }

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                ForEach(visibleSections) { section in
                    HStack {
                        Text(section.title)
                        Spacer()
                        Button {
                            // Don't allow disabling the last section.
                            guard store.settings.enabledSections.count > 1 else { return }
                            store.settings.enabledSections.removeAll { $0 == section.type }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.settings.enabledSections.count <= 1)
                    }
                }
                .onMove { offsets, destination in
                    store.settings.enabledSections.move(fromOffsets: offsets, toOffset: destination)
                }
            } header: {
                Text("Visible — drag to reorder", bundle: L10n.bundle)
            }

            if !hiddenSections.isEmpty {
                Section(L10n.string("Hidden")) {
                    ForEach(hiddenSections) { section in
                        Button {
                            // Append to the end of the user's current order, rather than
                            // recomputing from canonical order, so re-enabling a section
                            // doesn't discard any reordering already done above.
                            store.settings.enabledSections.append(section.type)
                        } label: {
                            HStack {
                                Text(section.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(L10n.string("Visible Sections"))
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - SponsorBlockExcludedChannelsView

/// Lists channels excluded from SponsorBlock processing.
/// Channels can be added from ChannelView and removed here via swipe-to-delete.
struct SponsorBlockExcludedChannelsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let sortedChannels = store.settings.sponsorBlockExcludedChannels
            .sorted { $0.value.localizedCompare($1.value) == .orderedAscending }
        return List {
            if sortedChannels.isEmpty {
                ContentUnavailableView(
                    L10n.string("No Excluded Channels"),
                    systemImage: "person.crop.circle.badge.minus",
                    description: Text(
                        "Open a channel and tap \u{201C}Exclude from SponsorBlock\u{201D} to add it here.",
                        bundle: L10n.bundle)
                )
            } else {
                ForEach(sortedChannels, id: \.key) { channelId, title in
                    Text(title)
                }
                .onDelete { indices in
                    let ids = indices.map { sortedChannels[$0].key }
                    ids.forEach { store.settings.sponsorBlockExcludedChannels.removeValue(forKey: $0) }
                }
            }
        }
        .navigationTitle(L10n.string("Excluded Channels"))
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        #endif
    }
}
