import SmartTubeIOSCore
import SwiftUI

// MARK: - HomeView
//
// YouTube-style home tab.  A horizontal chip bar at the top lets the user
// switch between every available section:
//   • "Home"  chip  → multi-shelf overview (Subscriptions row,
//                      Recommended row) driven by HomeViewModel.
//   • Any other chip → full-screen video feed for that section driven by a
//                      dedicated BrowseViewModel instance.

public struct HomeView: View {
    @State private var homeVM: HomeViewModel
    @State private var sectionVM: BrowseViewModel
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif

    // "Home" is always first; its type is .home.
    @State private var selectedSection: BrowseSection = BrowseSection.allSections[0]
    @State private var selectedVideo: Video?
    @State private var selectedPlaylist: Video?
    @State private var shortsPresentation: ShortsPresentation?
    @State private var channelDestination: ChannelDestination?
    /// #62: nil = show every subscribed channel's videos. Session-only (not persisted
    /// to AppSettings) — reset when the Subscriptions videoGroups reload from scratch,
    /// same lifetime as a search filter rather than a durable preference.
    @State private var subscriptionsChannelFilter: String? = nil
    @State private var showSignIn = false
    @State private var queueVideosCount: Int = 0
    // Auto-retry tracking: record the type-specific video count at the moment a
    // scroll trigger fires so onChange can detect whether the next page helped.
    @State private var needsMoreShorts = false
    #if os(macOS)
    /// Tracks the video ID for which the TOS player hit a fatal embed error so
    /// the NavigationDestination can fall through to the standard PlayerView for
    /// that video only. Cleared when a different video is tapped.
    @State private var tosPlayerFallbackVideoId: String? = nil
    #endif
    @State private var shortsCountAtTrigger = 0
    @State private var needsMoreNonShorts = false
    @State private var nonShortsCountAtTrigger = 0
    #if os(tvOS)
    @FocusState private var focusedSection: BrowseSection?
    #endif
    private var visibleSections: [BrowseSection] {
        let types = store.settings.enabledSections
        var all: [BrowseSection] =
            types.isEmpty
            ? BrowseSection.defaultSections
            : types.compactMap { type in BrowseSection.allSections.first { $0.type == type } }
        // Always keep a "Recommended" chip directly after the "Home" chip so the
        // user can filter to only recommended videos regardless of settings.
        if !all.contains(where: { $0.type == .recommended }),
            let homeIdx = all.firstIndex(where: { $0.type == .home })
        {
            all.insert(BrowseSection(type: .recommended), at: homeIdx + 1)
        }
        if store.settings.hideShorts {
            return all.filter { $0.type != .shorts }
        }
        return all
    }

    public init(api: InnerTubeAPI) {
        _homeVM = State(initialValue: HomeViewModel(api: api))
        _sectionVM = State(initialValue: BrowseViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            chipBar
            #if !os(tvOS)
            Divider()
            #endif
            contentArea
                #if !os(iOS)
            .navigationDestination(item: $selectedVideo) { video in
                #if os(macOS)
                if store.settings.useTOSPlayerOnMac && tosPlayerFallbackVideoId != video.id {
                    TOSPlayerView(video: video, api: api) {
                        tosPlayerFallbackVideoId = video.id
                    }
                    .environment(store)
                    .onDisappear { tosPlayerFallbackVideoId = nil }
                } else {
                    PlayerView(video: video, api: api)
                }
                #else
                PlayerView(video: video, api: api)
                #endif
            }
                #endif
                .navigationDestination(item: $selectedPlaylist) { stub in
                    PlaylistView(playlistId: stub.id, playlistTitle: stub.title, api: api)
                }
                .navigationDestination(item: $channelDestination) { dest in
                    ChannelView(channelId: dest.channelId)
                }
                #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(iOS)
        // Player cover is centralised in MainTabView; deep-link handled there too.
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $shortsPresentation) { target in
            ShortsPlayerView(videos: target.videos, startIndex: target.startIndex, api: api)
        }
        #endif
        .sheet(isPresented: $showSignIn) { SignInView() }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        #if os(iOS)
        // App Intents ("Open Subscriptions in SmartTube"): RootView switches to this tab.
        // A section hidden in Settings still opens, just without a chip.
        .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSection)) { note in
            guard let raw = note.userInfo?["section"] as? String,
                let type = BrowseSection.SectionType(rawValue: raw)
            else { return }
            selectedSection =
                visibleSections.first { $0.type == type }
                ?? BrowseSection(id: type.rawValue, title: type.defaultTitle, type: type)
        }
        #endif
        .onChange(of: visibleSections) { _, newSections in
            if !newSections.contains(selectedSection), let first = newSections.first {
                selectedSection = first
            }
        }
        .task(id: auth.accessToken) {
            await homeVM.updateAuthToken(auth.accessToken)
            await sectionVM.updateAuthToken(auth.accessToken)
        }
        .task(id: selectedSection) {
            // Reset auto-retry flags when switching sections to prevent stale
            // triggers from a previous section firing on the new section's content.
            needsMoreShorts = false
            needsMoreNonShorts = false
            // #62: leaving Subscriptions (or a hard refresh landing back on it) drops
            // any channel filter — a stale filter pointing at a channel that no longer
            // has videos in a freshly reloaded feed would otherwise silently show "no
            // videos" with no obvious explanation.
            subscriptionsChannelFilter = nil
            if selectedSection.type == .playlists {
                queueVideosCount = await CurrentQueueStore.shared.videos.count
            } else if selectedSection.type != .home {
                // Safety net: if sectionVM somehow fell out of sync with selectedSection
                // (e.g., the chip action raced with an in-flight cancellation, or an
                // @Observable tracking gap left the view empty), force a reload.
                if sectionVM.currentSection != selectedSection {
                    sectionVM.select(section: selectedSection)
                }
            }
        }
    }

    // MARK: - Chip bar

    private var chipBar: some View {
        #if os(tvOS)
        HStack(spacing: 8) {
            ForEach(visibleSections) { section in
                chipButton(section: section)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .focusSection()
        .defaultFocus($focusedSection, selectedSection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.chipBar")
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleSections) { section in
                    chipButton(section: section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier("home.chipBar")
        #endif
    }

    private func chipButton(section: BrowseSection) -> some View {
        let isSelected = selectedSection == section
        let action = {
            let isNewSection = selectedSection != section
            if isNewSection { selectedSection = section }
            guard section.type != .home else { return }
            if isNewSection {
                sectionVM.select(section: section)
            } else if sectionVM.videoGroups.isEmpty && !sectionVM.isLoading {
                // Same chip re-tapped on an empty section — retry the load.
                // This handles failed fetches or cases where an observation gap
                // left the view showing an empty state despite data being available.
                sectionVM.reload(section: section)
            }
        }
        #if os(tvOS)
        let isFocused = focusedSection == section
        return Button(action: action) {
            Text(section.title)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    (isSelected || isFocused) ? Color.primary : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(
                    (isSelected || isFocused)
                        ? Color(white: colorScheme == .dark ? 0 : 1)
                        : Color.primary
                )
                .focusEffectDisabled()
        }
        .buttonStyle(.borderless)
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: focusedSection)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(section.title)
        .accessibilityIdentifier("chip.\(section.title)")
        .focused($focusedSection, equals: section)
        #else
        return Button(action: action) {
            Text(section.title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.primary : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(
                    isSelected
                        ? Color(white: colorScheme == .dark ? 0 : 1)
                        : Color.primary
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        #endif
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if selectedSection.type == .home {
            if auth.isSignedIn {
                homeShelves
            } else {
                homeSignedOutPrompt
            }
        } else if selectedSection.type == .channels {
            channelListFeed
                .accessibilityIdentifier("home.sectionContainer")
        } else {
            sectionFeed
                .accessibilityIdentifier("home.sectionContainer")
        }
    }

    @ViewBuilder
    private var channelListFeed: some View {
        if sectionVM.isLoading && sectionVM.subscribedChannels.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sectionVM.subscribedChannels.isEmpty && !sectionVM.isLoading {
            feedEmptyState
        } else {
            ChannelListView(channels: sectionVM.subscribedChannels) { channel in
                channelDestination = ChannelDestination(channelId: channel.id)
            }
        }
    }

    private var homeSignedOutPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbol.personCircleQuestion)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Sign in to see your feed")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Sign In") { showSignIn = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Home shelves  (unified interleaved feed)

    private var homeShelves: some View {
        Group {
            if homeVM.isLoadingAny && homeVM.mergedVideos.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let hideShorts = store.settings.hideShorts
                let regularVideos = homeVM.homeRegularVideos
                let shortsVideos = hideShorts ? [] : homeVM.homeShortsVideos
                // ShortsRowSection is placed OUTSIDE the ScrollView so it stays
                // pinned at the top while the video grid scrolls beneath it.
                VStack(spacing: 0) {
                    if !shortsVideos.isEmpty {
                        ShortsRowSection(
                            videos: shortsVideos,
                            onSelect: { selectVideo($0, from: shortsVideos) },
                            accessibilityID: "home.shortsRow",
                            loadMore: { homeVM.loadNextShortsPage() }
                        )
                        #if os(tvOS)
                        .focusSection()
                        #endif
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VideoGridSection(
                                videos: regularVideos,
                                onSelect: { selectVideo($0, from: regularVideos) },
                                loadMore: { homeVM.loadMoreMerged() }
                            )
                            let isLoadingMore = homeVM.sections.contains { $0.isLoadingMore }
                            if isLoadingMore {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        }
                    }
                    .refreshable { homeVM.load() }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }

    // MARK: - Section feed  (non-Home chips)

    @ViewBuilder
    private var sectionFeed: some View {
        if sectionVM.isLoading && sectionVM.videoGroups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sectionVM.videoGroups.isEmpty && !sectionVM.isLoading {
            feedEmptyState
        } else {
            feedContent
        }
    }

    private var feedContent: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let isShorts = selectedSection.type == .shorts
        let applyHideShorts = hideShorts && selectedSection.type != .history
        // #121: History is the one place watched videos are the point — never filtered.
        let applyHideWatched = store.settings.hideWatchedVideos && selectedSection.type != .history
        let hideWatchedThreshold = store.settings.hideWatchedThreshold
        // #62: channel filter only applies to (and is only shown for) Subscriptions —
        // it wouldn't make sense for a single-source list like a specific Channel page,
        // and Home mixes recommendations that don't necessarily come from a subscription.
        let isSubscriptions = selectedSection.type == .subscriptions
        let channelFilter = isSubscriptions ? subscriptionsChannelFilter : nil

        // Pinned shorts row: shown above the scrollable content for all chips
        // except the Shorts chip itself (which shows a full vertical list instead).
        // For Recommended, use the separately-fetched recommendedShortsVideos so
        // there is no double-counting with the grid below.
        // For all other chips, extract any shorts that appear in the video groups.
        let pinnedShorts: [Video]
        if isShorts || applyHideShorts {
            pinnedShorts = []
        } else if selectedSection.type == .recommended {
            pinnedShorts = sectionVM.recommendedShortsVideos.filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
        } else {
            pinnedShorts = sectionVM.videoGroups.flatMap(\.videos).filter(\.isShort).filter {
                !hideLiveShorts || !($0.isLive && $0.isShort)
            }
        }

        let rowGroups: [VideoGroup] = sectionVM.videoGroups.filter { $0.layout == .row }.map { g in
            var copy = g
            var videos = g.videos
            if applyHideShorts { videos = videos.filter { !$0.isShort } }
            if hideLiveShorts { videos = videos.filter { !($0.isLive && $0.isShort) } }
            if hideVideoPremieres { videos = videos.filter { !$0.isUpcoming } }
            if applyHideWatched { videos = videos.filter { !$0.isWatched(threshold: hideWatchedThreshold) } }
            if let channelFilter { videos = videos.filter { $0.channelId == channelFilter } }
            copy.videos = videos
            return copy
        }
        // For non-Shorts chips, exclude shorts from the grid — they appear in the
        // pinned row above. For the Shorts chip itself, keep all videos.
        // VStack (not LazyVStack) is required here. LazyVGrid inside LazyVStack
        // collapses to zero height — grid items become invisible and non-tappable
        // because LazyVStack never provides a measured height to LazyVGrid.
        // Row groups are few (typically ≤15 carousels) so eager rendering is fine.
        let gridVideos = sectionVM.videoGroups.filter { $0.layout != .row }
            .flatMap(\.videos)
            .filter { !applyHideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
            .filter { !applyHideWatched || !$0.isWatched(threshold: hideWatchedThreshold) }
            .filter { channelFilter == nil || $0.channelId == channelFilter }
            .filter { isShorts || !$0.isShort }

        // #62: distinct (channelId, channelTitle) pairs across the currently loaded
        // Subscriptions videos, for the channel-filter menu. Derived client-side from
        // whatever's already loaded — no extra network call — so it only ever offers
        // channels with at least one video in the feed right now, not literally every
        // channel the user follows (a channel with zero recent uploads has nothing to
        // filter to anyway).
        let availableChannels: [(id: String, title: String)] = {
            guard isSubscriptions else { return [] }
            var seen = Set<String>()
            var result: [(id: String, title: String)] = []
            for video in sectionVM.videoGroups.flatMap(\.videos) {
                guard let channelId = video.channelId, seen.insert(channelId).inserted else { continue }
                result.append((id: channelId, title: video.channelTitle))
            }
            return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }()

        // The raw last video of the last group is the canonical pagination trigger for
        // loadMoreIfNeeded — it checks membership in videoGroups.last, so passing a
        // filtered (non-short) video won't match if the last group is all-shorts.
        // Both the shorts row and the grid use this as their loadMore trigger so
        // either reaching the end of the shorts row OR scrolling to the bottom of
        // the main content independently triggers the next page load.
        let paginationTrigger: Video? = sectionVM.videoGroups.last?.videos.last

        return VStack(spacing: 0) {
            // #62: channel filter, Subscriptions only. Hidden entirely when there's
            // nothing to filter between (0 or 1 distinct channels loaded).
            if isSubscriptions, availableChannels.count > 1 {
                HStack {
                    Menu {
                        Button {
                            subscriptionsChannelFilter = nil
                        } label: {
                            if subscriptionsChannelFilter == nil {
                                Label("All Channels", systemImage: "checkmark")
                            } else {
                                Text("All Channels")
                            }
                        }
                        Divider()
                        ForEach(availableChannels, id: \.id) { channel in
                            Button {
                                subscriptionsChannelFilter = channel.id
                            } label: {
                                if subscriptionsChannelFilter == channel.id {
                                    Label(channel.title, systemImage: "checkmark")
                                } else {
                                    Text(channel.title)
                                }
                            }
                        }
                    } label: {
                        Label(
                            availableChannels.first(where: { $0.id == subscriptionsChannelFilter })?.title
                                ?? "All Channels",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("home.subscriptionsChannelFilter")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            // Pinned ShortsRowSection — outside the ScrollView so it stays fixed
            // at the top while the video content below scrolls.
            if !pinnedShorts.isEmpty {
                ShortsRowSection(
                    videos: pinnedShorts,
                    onSelect: { selectVideo($0, from: pinnedShorts) },
                    accessibilityID: selectedSection.type == .recommended
                        ? "recommended.shortsRow"
                        : "browse.shortsRow",
                    loadMore: {
                        // Reaching the end of the shorts row means the user wants more
                        // content of ALL types — set both flags so onChange keeps
                        // retrying until both shorts AND non-shorts have grown (or pages
                        // are exhausted). Without setting needsMoreNonShorts here, pages
                        // that arrive with only non-shorts would not re-trigger the loop.
                        let allVideos = sectionVM.videoGroups.flatMap(\.videos)
                        shortsCountAtTrigger = allVideos.filter(\.isShort).count
                        nonShortsCountAtTrigger = allVideos.filter { !$0.isShort }.count
                        needsMoreShorts = true
                        needsMoreNonShorts = true
                        if let last = paginationTrigger {
                            sectionVM.loadMoreIfNeeded(lastVideo: last)
                        }
                    }
                )
                #if os(tvOS)
                .focusSection()
                #endif
            }
            if isShorts {
                // Shorts chip: vertical portrait card list driven by ShortsRowSection's
                // internal ScrollView. frame(maxHeight: .infinity) ensures the internal
                // ScrollView gets the full remaining height rather than sizing to content.
                let shortsVideos = sectionVM.videoGroups.flatMap(\.videos)
                ShortsRowSection(
                    videos: shortsVideos,
                    onSelect: { selectVideo($0, from: shortsVideos) },
                    accessibilityID: "shorts.section",
                    loadMore: {
                        // Set retry flag so onChange keeps fetching pages until the
                        // Shorts chip has more videos — guards in loadMoreIfNeeded
                        // prevent duplicate in-flight requests.
                        shortsCountAtTrigger = sectionVM.videoGroups.flatMap(\.videos).count
                        needsMoreShorts = true
                        if let last = paginationTrigger {
                            sectionVM.loadMoreIfNeeded(lastVideo: last)
                        }
                    },
                    scrollAxis: .vertical
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(tvOS)
                .focusSection()
                #endif
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if selectedSection.type == .playlists, queueVideosCount > 0 {
                            currentQueueRow
                        }
                        ForEach(rowGroups) { group in
                            if let title = group.title, !title.isEmpty {
                                Text(title)
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)
                            }
                            VideoRowSection(videos: group.videos, onSelect: { selectVideo($0, from: group.videos) })
                        }
                        if !gridVideos.isEmpty {
                            VideoGridSection(
                                videos: gridVideos,
                                onSelect: { selectVideo($0, from: gridVideos) },
                                loadMore: {
                                    // Reaching the end of the grid means the user wants
                                    // more content of ALL types — set both flags so
                                    // onChange keeps retrying until both non-shorts AND
                                    // shorts have grown (or pages are exhausted). Without
                                    // setting needsMoreShorts here, pages that contain
                                    // only shorts (no new grid videos) would stall the
                                    // retry — and the pinned shorts row would never grow
                                    // unless the user also manually scrolls it to the end.
                                    let allVideos = sectionVM.videoGroups.flatMap(\.videos)
                                    nonShortsCountAtTrigger = allVideos.filter { !$0.isShort }.count
                                    shortsCountAtTrigger = allVideos.filter(\.isShort).count
                                    needsMoreNonShorts = true
                                    needsMoreShorts = true
                                    if let last = paginationTrigger {
                                        sectionVM.loadMoreIfNeeded(lastVideo: last)
                                    }
                                }
                            )
                        }
                        if sectionVM.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                }
                .accessibilityIdentifier("home.sectionFeed")
                .refreshable { sectionVM.loadContent(refresh: true) }
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
        .onChange(of: sectionVM.videoGroups.flatMap(\.videos).count) { _, _ in
            // After each page load, check whether the type(s) each trigger was
            // waiting for actually appeared. Compare against the count snapshot
            // recorded when the scroll trigger fired — NOT the last-page slice,
            // which for mergeIntoFirstGroup sections is the entire accumulated
            // list (making "does last page have shorts?" always true after the
            // first short ever arrived).
            //
            // loadMoreIfNeeded's own guards (nextPageToken, isLoadingMore) prevent
            // runaway loops — pagination stops when pages are exhausted or a load
            // is already in flight.
            let isShortsSectionActive = selectedSection.type == .shorts
            let applyHide = store.settings.hideShorts && selectedSection.type != .history
            guard !applyHide,
                let trigger = sectionVM.videoGroups.last?.videos.last
            else { return }

            let allVideos = sectionVM.videoGroups.flatMap(\.videos)
            var shouldTrigger = false

            if isShortsSectionActive {
                // Shorts chip: all videos are shorts — compare total count against snapshot.
                // Keep triggering until the count grows or pages are exhausted.
                if needsMoreShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    if allVideos.count > shortsCountAtTrigger {
                        needsMoreShorts = false  // new shorts arrived — satisfied
                    } else if !hasMorePages {
                        needsMoreShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had nothing new — fetch another
                    }
                }
            } else {
                // Mixed feed: check each type independently.
                if needsMoreShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    let currentShortsCount = allVideos.filter(\.isShort).count
                    if currentShortsCount > shortsCountAtTrigger {
                        needsMoreShorts = false  // pinned row got new shorts — satisfied
                    } else if !hasMorePages {
                        needsMoreShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had no new shorts — fetch another
                    }
                }

                if needsMoreNonShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    let currentNonShortsCount = allVideos.filter { !$0.isShort }.count
                    if currentNonShortsCount > nonShortsCountAtTrigger {
                        needsMoreNonShorts = false  // grid got new regular videos — satisfied
                    } else if !hasMorePages {
                        needsMoreNonShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had no new regulars — fetch another
                    }
                }
            }

            if shouldTrigger {
                sectionVM.loadMoreIfNeeded(lastVideo: trigger)
            }
        }
    }

    @ViewBuilder private var currentQueueRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.number")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Queue")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(queueVideosCount) video\(queueVideosCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlaylist = Video(
                id: CurrentQueueStore.playlistID,
                title: "Current Queue",
                channelTitle: ""
            )
        }
        .accessibilityIdentifier("home.currentQueueRow")
        Divider().padding(.horizontal)
    }

    private var feedEmptyState: some View {
        VStack(spacing: 16) {
            if sectionVM.isAuthRequired && !auth.isSignedIn {
                Image(systemName: AppSymbol.personCircleWarning)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Sign in to see this section")
                    .font(.title3)
                Text("Your Google account is required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Sign In") { showSignIn = true }
                    .buttonStyle(.borderedProminent)
            } else if !auth.isSignedIn && (selectedSection.type == .subscriptions || selectedSection.type == .channels)
            {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Follow channels to see their latest videos here")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text("Search for a channel and tap Follow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Search") {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: AppSymbol.tvPlay)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Nothing here yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Refresh") { sectionVM.loadContent(refresh: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Video selection

    private func selectVideo(_ video: Video, from groupVideos: [Video]) {
        if video.playlistId == video.id {
            selectedPlaylist = video
        } else if video.isShort {
            #if os(iOS)
            let shorts = groupVideos.filter { $0.isShort }
            let idx = shorts.firstIndex(where: { $0.id == video.id }) ?? 0
            shortsPresentation = ShortsPresentation(videos: shorts, startIndex: idx)
            #else
            selectedVideo = video
            #endif
        } else {
            #if os(iOS)
            playerRouter.open(video: video, api: api)
            #else
            selectedVideo = video
            #endif
        }
    }
}
