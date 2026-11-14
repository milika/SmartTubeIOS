import SmartTubeIOSCore
import SwiftUI

// MARK: - SearchView
//
// Search interface with live suggestions and paginated results.
// Mirrors the Android `SearchTagsActivity`.

public struct SearchView: View {
    @Environment(SearchViewModel.self) private var vm
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @State private var selectedVideo: Video?
    @State private var channelDestination: ChannelDestination?
    @State private var showFilterSheet = false
    @FocusState private var isSearchFocused: Bool
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if !vm.query.isEmpty {
                filterChipsRow
            }
            Group {
                #if os(tvOS)
                if vm.isLoading || !vm.results.isEmpty {
                    resultsView
                } else if vm.query.isEmpty {
                    suggestionsListView
                } else {
                    noResultsView
                }
                #else
                if isSearchFocused {
                    suggestionsListView
                } else if vm.isLoading || !vm.results.isEmpty {
                    resultsView
                } else if !vm.query.isEmpty {
                    noResultsView
                } else {
                    suggestionsListView
                }
                #endif
            }
        }
        #if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #elseif os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $channelDestination) { dest in
            ChannelView(channelId: dest.channelId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        .sheet(isPresented: $showFilterSheet) {
            SearchFilterSheet(current: vm.filter) { newFilter in
                vm.applyFilter(newFilter)
            }
        }
        .task(id: vm.query) { await vm.updateSuggestions(for: vm.query) }
        .onChange(of: isSearchFocused) { _, focused in
            if focused { Task { await vm.updateSuggestions(for: vm.query) } }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        @Bindable var vm = vm
        return HStack(spacing: 8) {
            Image(systemName: AppSymbol.search)
                .foregroundStyle(.secondary)
            TextField(L10n.string("Search YouTube"), text: $vm.query)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("search.bar")
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
                .onSubmit {
                    vm.search()
                    isSearchFocused = false
                }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: AppSymbol.xmarkCircle)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.clearButton")
            }
            Button {
                showFilterSheet = true
            } label: {
                Image(
                    systemName: vm.filter.isDefault
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
                .foregroundStyle(vm.filter.isDefault ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.filterButton")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Active filter chips

    @ViewBuilder
    private var filterChipsRow: some View {
        if !vm.filter.isDefault {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if vm.filter.sortOrder != .relevance {
                        FilterChip(label: vm.filter.sortOrder.label) {
                            var f = vm.filter
                            f.sortOrder = .relevance
                            vm.applyFilter(f)
                        }
                    }
                    if vm.filter.uploadDate != .anytime {
                        FilterChip(label: vm.filter.uploadDate.label) {
                            var f = vm.filter
                            f.uploadDate = .anytime
                            vm.applyFilter(f)
                        }
                    }
                    if vm.filter.type != .any {
                        FilterChip(label: vm.filter.type.label) {
                            var f = vm.filter
                            f.type = .any
                            vm.applyFilter(f)
                        }
                    }
                    if vm.filter.duration != .any {
                        FilterChip(label: vm.filter.duration.label) {
                            var f = vm.filter
                            f.duration = .any
                            vm.applyFilter(f)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            Divider()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let displayResults = vm.results
            .filter { !hideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
        return ScrollView {
            if vm.isLoading && vm.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
            VideoGridSection(
                videos: displayResults,
                onSelect: { video in
                    let captured = displayResults
                    Task { @MainActor in
                        await CurrentQueueStore.shared.replaceAll(with: captured)
                        let startIdx = captured.firstIndex(where: { $0.id == video.id }) ?? 0
                        let toPlay = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                        #if os(iOS)
                        playerRouter.open(video: toPlay, api: api)
                        #else
                        selectedVideo = toPlay
                        #endif
                    }
                },
                loadMore: vm.loadMore
            )
            if vm.isLoading && !vm.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
        .accessibilityIdentifier("search.results")
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        #endif
    }

    // MARK: - Suggestions list (history + recommended/live)

    private var suggestionsListView: some View {
        let suggestionsHeader =
            vm.query.isEmpty ? L10n.string("Recommended") : L10n.string("Suggestions")
        return List {
            // History section — only shown when there are matching entries
            if !vm.filteredHistory.isEmpty {
                Section(header: Text("Recent", bundle: L10n.bundle).font(.caption).foregroundStyle(.secondary)) {
                    ForEach(vm.filteredHistory) { entry in
                        Button {
                            vm.query = entry.query
                            vm.search()
                            isSearchFocused = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(entry.query)
                                    .foregroundStyle(.primary)
                                Spacer()
                                #if os(iOS)
                                Button {
                                    vm.removeHistoryEntry(entry.query)
                                } label: {
                                    Image(systemName: AppSymbol.xmark)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.string("Remove \(entry.query) from history"))
                                #endif
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.history.\(entry.query)")
                    }
                    Button(role: .destructive) {
                        vm.clearHistory()
                    } label: {
                        Text("Clear History", bundle: L10n.bundle)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("search.history.clearAll")
                }
            }

            // Suggestions / Recommended section (existing behaviour)
            Section(header: Text(suggestionsHeader).font(.caption).foregroundStyle(.secondary)) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        vm.query = suggestion
                        vm.search()
                        isSearchFocused = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: AppSymbol.search)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(suggestion)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                vm.query = suggestion
                            } label: {
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("search.suggestionsContainer")
        // Tapping empty list space (outside a row) must dismiss the keyboard.
        // Task #202: the resultsView and noResultsView already had this gesture
        // but suggestionsListView (shown while keyboard is open) was missing it.
        // .contentShape(Rectangle()) makes the transparent empty space tappable.
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbol.search)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Search for videos, channels & playlists", bundle: L10n.bundle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbol.questionCircle)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No results for \"\(vm.query)\"", bundle: L10n.bundle)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        #if os(iOS)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        #endif
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: AppSymbol.xmark)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.tint.opacity(0.15), in: Capsule())
        .foregroundStyle(.tint)
    }
}

// MARK: - SearchFilterSheet

struct SearchFilterSheet: View {
    let current: SearchFilter
    let onApply: (SearchFilter) -> Void

    @State private var draft: SearchFilter
    @Environment(\.dismiss) private var dismiss

    init(current: SearchFilter, onApply: @escaping (SearchFilter) -> Void) {
        self.current = current
        self.onApply = onApply
        _draft = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("Sort by")) {
                    Picker(L10n.string("Sort"), selection: $draft.sortOrder) {
                        ForEach(SearchFilter.SortOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(L10n.string("Upload date")) {
                    Picker(L10n.string("Upload date"), selection: $draft.uploadDate) {
                        ForEach(SearchFilter.UploadDate.allCases, id: \.self) { date in
                            Text(date.label).tag(date)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(L10n.string("search.filter.type")) {
                    Picker(L10n.string("search.filter.type"), selection: $draft.type) {
                        ForEach(SearchFilter.VideoType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(L10n.string("Duration")) {
                    Picker(L10n.string("Duration"), selection: $draft.duration) {
                        ForEach(SearchFilter.Duration.allCases, id: \.self) { dur in
                            Text(dur.label).tag(dur)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(L10n.string("Search filters"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Apply")) {
                        onApply(draft)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button(L10n.string("Reset")) { draft = .default }
                        .disabled(draft.isDefault)
                }
                #endif
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("search.filterSheet")
    }
}
