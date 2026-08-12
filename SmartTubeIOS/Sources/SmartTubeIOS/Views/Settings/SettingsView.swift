import SwiftUI
import AuthenticationServices
import SmartTubeIOSCore

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

    public init() {}

    public var body: some View {
        Form {
            accountSection
            playerSection
            generalSection
            uiSection
            sponsorBlockSection
            deArrowSection
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
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
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
                    Text(auth.accountName ?? "Unknown")
                }
                Button("Sign Out", role: .destructive) { auth.signOut() }
            } else {
                Button("Sign in with Google") { showSignIn = true }
                    .accessibilityIdentifier("settings.signInButton")
                    .sheet(isPresented: $showSignIn) { SignInView() }
            }
        }
    }

    // MARK: - Player

    private var playerSection: some View {
        @Bindable var store = store
        return Section("Player") {
            #if os(iOS)
            Picker("Video Player", selection: $store.settings.iOSPlayer) {
                Text("YouTube Player").tag(AppSettings.IOSPlayer.youtubeEmbed)
                Text("Native Player (Background Playback)").tag(AppSettings.IOSPlayer.native)
            }
            .accessibilityIdentifier("settings.iOSPlayerPicker")
            #endif

            Picker("Playback Speed", selection: $store.settings.playbackSpeed) {
                ForEach(AppSettings.availableSpeeds, id: \.self) { s in
                    Text(s == 1.0 ? "Normal" : "\(s, specifier: "%.2g")×").tag(s)
                }
            }

            #if !os(iOS)
            Picker("Max Resolution", selection: $store.settings.preferredQuality) {
                ForEach(AppSettings.VideoQuality.allCases, id: \.self) { q in
                    Text(q.rawValue.capitalized).tag(q)
                }
            }
            .accessibilityIdentifier("settings.preferredQualityPicker")

            Picker("Preferred Audio Language", selection: $store.settings.preferredAudioLanguage) {
                Text("System Default").tag(nil as String?)
                Divider()
                Text("English").tag("en" as String?)
                Text("Spanish").tag("es" as String?)
                Text("French").tag("fr" as String?)
                Text("German").tag("de" as String?)
                Text("Japanese").tag("ja" as String?)
                Text("Korean").tag("ko" as String?)
                Text("Portuguese (Brazil)").tag("pt-BR" as String?)
                Text("Chinese (Simplified)").tag("zh-Hans" as String?)
                Divider()
                Text("Original Track Only").tag("original" as String?)
            }
            .accessibilityIdentifier("settings.preferredAudioLanguageRow")
            #endif

            #if os(tvOS)
            Picker("Seek Back", selection: $store.settings.seekBackSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s").tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekBackRow")
            Picker("Seek Forward", selection: $store.settings.seekForwardSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s").tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekForwardRow")
            #elseif os(macOS)
            Stepper(
                "Seek Back: \(store.settings.seekBackSeconds) s",
                value: $store.settings.seekBackSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekBackRow")
            Stepper(
                "Seek Forward: \(store.settings.seekForwardSeconds) s",
                value: $store.settings.seekForwardSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekForwardRow")
            #endif

            #if !os(iOS)
            Picker("Hide Controls After", selection: $store.settings.controlsHideTimeout) {
                Text("2s").tag(2)
                Text("3s").tag(3)
                Text("4s").tag(4)
                Text("5s").tag(5)
                Text("8s").tag(8)
                Text("10s").tag(10)
            }

            Picker("Video Fit", selection: $store.settings.videoGravityMode) {
                Text("Fit (letterbox)").tag(AppSettings.VideoGravityMode.fit)
                Text("Fill (crop)").tag(AppSettings.VideoGravityMode.fill)
            }
            #endif

            Toggle("Loop Video", isOn: $store.settings.loopEnabled)
            Toggle("Shuffle", isOn: $store.settings.shuffleEnabled)

            Toggle("Autoplay next video", isOn: $store.settings.autoplayEnabled)
            Toggle("Background Playback", isOn: $store.settings.backgroundPlaybackEnabled)
                #if os(iOS)
                .disabled(store.effectiveIOSPlayer == .youtubeEmbed)
                .accessibilityIdentifier("settings.backgroundPlaybackToggle")
                #endif
            #if os(iOS)
            if store.effectiveIOSPlayer == .youtubeEmbed {
                Text("Background Playback requires the Native Player.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.backgroundPlaybackHint")
            }
            #endif
            #if !os(iOS)
            Toggle("Prefer H.264 Codec", isOn: $store.settings.preferH264)
                .accessibilityIdentifier("settings.preferH264Toggle")
            #endif
        }
    }

    // MARK: - General

    private var generalSection: some View {
        @Bindable var store = store
        return Section("General") {
            Picker("Watch History", selection: $store.settings.historyState) {
                Text("Enabled").tag(AppSettings.HistoryState.enabled)
                Text("Disabled").tag(AppSettings.HistoryState.disabled)
            }
            Toggle("Sync to iCloud", isOn: $store.settings.iCloudSyncEnabled)
                .accessibilityIdentifier("settings.iCloudSyncToggle")
        }
    }

    // MARK: - UI

    private var uiSection: some View {
        @Bindable var store = store
        return Section("Interface") {
            Picker("Theme", selection: $store.settings.themeName) {
                ForEach(AppSettings.ThemeName.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .accessibilityIdentifier("settings.themeRow")
            Toggle("Hide Shorts", isOn: $store.settings.hideShorts)
                .accessibilityIdentifier("settings.hideShortsToggle")
            Toggle("Hide Live Shorts", isOn: $store.settings.hideLiveShorts)
                .accessibilityIdentifier("settings.hideLiveShortsToggle")
            Toggle("Hide Video Premieres", isOn: $store.settings.hideVideoPremieres)
                .accessibilityIdentifier("settings.hideVideoPremieresToggle")
            Toggle("Per-Device Recommendations", isOn: $store.settings.perDeviceRecommendationsEnabled)
                .accessibilityIdentifier("settings.perDeviceRecommendationsToggle")
            Toggle("Compact Thumbnails", isOn: $store.settings.compactThumbnails)
            NavigationLink("Visible Sections") {
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
            Toggle("Enable SponsorBlock", isOn: $store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier("settings.sponsorBlockToggle")

            if store.settings.sponsorBlockEnabled {
                ForEach(SponsorSegment.Category.allCases, id: \.self) { cat in
                    HStack {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 10, height: 10)
                        Picker(cat.displayName, selection: Binding(
                            get: { store.settings.sponsorBlockActions[cat] ?? .nothing },
                            set: { store.settings.sponsorBlockActions[cat] = $0 }
                        )) {
                            Text("Skip").tag(AppSettings.SponsorBlockAction.skip)
                            Text("Show Toast").tag(AppSettings.SponsorBlockAction.showToast)
                            Text("Nothing").tag(AppSettings.SponsorBlockAction.nothing)
                        }
                        .accessibilityIdentifier("settings.sponsorBlock.\(cat.rawValue)")
                    }
                }

                // Minimum segment duration
                Picker("Min. Segment Length", selection: $store.settings.sponsorBlockMinSegmentDuration) {
                    Text("Off").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }

                // Excluded channels
                NavigationLink("Excluded Channels (\(store.settings.sponsorBlockExcludedChannels.count))") {
                    SponsorBlockExcludedChannelsView()
                }
                .accessibilityIdentifier("settings.sponsorBlockExcludedChannels")
            }
        } header: {
            Text("SponsorBlock")
        } footer: {
            Text("Skip \u{2014} auto-skips. Show Toast \u{2014} shows a skip button. Nothing \u{2014} plays through.")
        }
    }

    // MARK: - DeArrow

    private var deArrowSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Enable DeArrow", isOn: $store.settings.deArrowEnabled)
        } header: {
            Text("DeArrow")
        } footer: {
            Text("Replace clickbait titles and thumbnails with community-sourced alternatives.")
        }
    }

    // MARK: - Experimental (macOS)

    #if os(macOS)
    private var experimentalSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("IFrame Player (TOS-compliant, shows ads)", isOn: $store.settings.useTOSPlayerOnMac)
                .accessibilityIdentifier("settings.useTOSPlayerOnMacToggle")
        } header: {
            Text("Experimental")
        } footer: {
            Text("Uses YouTube's official embedded player instead of the direct stream pipeline. Quality selection and downloads are unavailable. Ads will play. Useful for videos that refuse to play via the standard path.")
        }
    }
    #endif

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            #if os(tvOS)
            Button {
                showGithubQR = true
            } label: {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #else
            Link(destination: URL(string: "https://github.com/milika/SmartTubeIOS")!) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #endif
            Button {
                CrashlyticsLogger.sendDiagnosticReport()
                reportSent = true
            } label: {
                if reportSent {
                    Label("Report Sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Send Diagnostic Report", systemImage: "ladybug")
                }
            }
            .disabled(reportSent)
            .accessibilityIdentifier("settings.sendDiagnosticReportButton")
            Button("Reset All Settings", role: .destructive) { store.reset() }
                .accessibilityIdentifier("settings.resetAllButton")
        } header: {
            Text("About")
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

                    Text("SmartTube on GitHub")
                        .font(.largeTitle).fontWeight(.bold)

                    Text("Scan the QR code with your phone to view the project on GitHub.")
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
                Label("Close", systemImage: "xmark")
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

    var body: some View {
        @Bindable var store = store
        List {
            ForEach(allSections) { section in
                Toggle(section.title, isOn: Binding(
                    get: { store.settings.enabledSections.contains(section.type) },
                    set: { enabled in
                        if enabled {
                            if !store.settings.enabledSections.contains(section.type) {
                                // Insert in canonical order
                                let ordered = allSections
                                    .filter { store.settings.enabledSections.contains($0.type) || $0.type == section.type }
                                    .map { $0.type }
                                store.settings.enabledSections = ordered
                            }
                        } else {
                            // Don't allow disabling the last section
                            if store.settings.enabledSections.count > 1 {
                                store.settings.enabledSections.removeAll { $0 == section.type }
                            }
                        }
                    }
                ))
            }
        }
        .navigationTitle("Visible Sections")
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
                    "No Excluded Channels",
                    systemImage: "person.crop.circle.badge.minus",
                    description: Text("Open a channel and tap \u{201C}Exclude from SponsorBlock\u{201D} to add it here.")
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
        .navigationTitle("Excluded Channels")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        #endif
    }
}
