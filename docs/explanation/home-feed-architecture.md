> status: unverified — moved from private repo agent-notes, not re-audited (2026-09-11)

# SmartTubeIOS Home Feed & Shorts Architecture

## Key Files
- **Core**: [SmartTubeIOSCore/InnerTubeAPI.swift](../../SmartTubeIOS/Sources/SmartTubeIOSCore/InnerTubeAPI.swift) - API layer & parsing
- **Core Models**: [SmartTubeIOSCore/VideoGroup.swift](../../SmartTubeIOS/Sources/SmartTubeIOSCore/VideoGroup.swift), [SmartTubeIOSCore/Video.swift](../../SmartTubeIOS/Sources/SmartTubeIOSCore/Video.swift)
- **ViewModels**: [HomeViewModel.swift](../../SmartTubeIOS/Sources/SmartTubeIOSCore/HomeViewModel.swift), [BrowseViewModel.swift](../../SmartTubeIOS/Sources/SmartTubeIOSCore/BrowseViewModel.swift)
- **Views**: [HomeView.swift](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Home/HomeView.swift), [BrowseView.swift](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/BrowseView.swift), [VideoCardView.swift](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/VideoCardView.swift)

## Data Models

### Video Model
```swift
public struct Video: Identifiable, Hashable, Codable, Sendable {
    public let id: String                     // videoId
    public var isShort: Bool                  // ← KEY: Shorts flag
    public var isLive: Bool
    public var isUpcoming: Bool
    public var duration: TimeInterval?
    // + title, channelTitle, channelId, thumbnail, badges, viewCount, publishedAt, etc.
}
```

### VideoGroup Model
```swift
public struct VideoGroup: Identifiable, Sendable {
    public var title: String?
    public var videos: [Video]
    public var nextPageToken: String?
    public var action: Action              // append/replace/remove/prepend
    public var layout: Layout              // ← KEY: .row (horizontal shelf) or .grid
}
```

### BrowseSection Model
```swift
public struct BrowseSection {
    public enum SectionType: String {
        case home, subscriptions, history, playlists, channels
        case shorts, music, gaming, news, live, sports, settings
    }
}
```

## API Endpoints & Browse IDs

### Home Feed Fetching
- **Endpoint**: `POST /youtubei/v1/browse`
- **Browse ID**: `"FEwhat_to_watch"` (personal recommendations when authenticated)
- **Authentication**: Uses TVHTML5 client on `youtubei.googleapis.com` when auth present, WEB client on `www.youtube.com` when unauthenticated
- **Returns**: Multi-shelf layout via `fetchHomeRows()` → `[VideoGroup]` with `layout: .row`

### Key Methods in InnerTubeAPI
- `fetchHome(continuationToken)` - Single VideoGroup (flat parse)
- `fetchHomeRows(continuationToken)` - **[VideoGroup]** - Multiple horizontal shelves
- `fetchShorts()` - Browse ID: `"FEshorts"` 
- `fetchShortsFeed(seedVideoId:)` / `fetchShortsFeedMore(continuation:)` - the Shorts *player* feed (Shorts tab, tapped shelf Shorts). Uses YouTube's reel sequence on TVHTML5 (`reel/reel_item_watch` for a seedless start, `reel/reel_watch_sequence` for pages; follow-up pages must send `continuation`, not `sequenceParams`), so it is personalised when signed in. `fetchShorts()` is only its last-resort fallback. See `ShortsFeedViewModel`.
- `fetchSubscriptions()` - Browse ID: `"FEsubscriptions"`
- `fetchHistory()` - Browse ID: `"FEhistory"`
- `fetchMusic()` - Browse ID: `"FEmusic_home"`
- `fetchGaming()` - Browse ID: `"FEgaming"`
- `fetchLive()` - Browse ID: `"FElive_home"`
- `fetchSports()` - Browse ID: `"FEsportsau"`

## Shorts vs Regular Video Detection

### In Parsing (InnerTubeAPI)
1. **reelItemRenderer** → always `isShort: true`
   - Parsed by `parseReelItemRenderer()`
   - Used in Shorts feeds

2. **TVHTML5 tileRenderer** → checks `style == "TILE_STYLE_YTLR_SHORTS"`
   - Parsed by `parseTileRenderer()`
   - Used in history/subs feeds (Android-style TVHTML5 responses)

3. **WEB videoRenderer** → checks `navigationEndpoint.reelWatchEndpoint != nil`
   - Parsed by `parseVideoRenderer()`
   - Regular videos have `watchEndpoint`, shorts have `reelWatchEndpoint`

### Logging
```swift
let shortsCount = videos.filter { $0.isShort }.count
tubeLog.notice("parseVideoGroup '...' → N videos (M regular, K shorts), nextPage=...")
```

## Home Feed Architecture

### HomeViewModel (`Sources/SmartTubeIOS/ViewModels/HomeViewModel.swift`)
Fetches **two shelves in parallel**:
```swift
public static let shelfSections: [BrowseSection] = [
    BrowseSection(id: "home", title: "Recommended", type: .home),
    BrowseSection(id: "subscriptions", title: "Subscriptions", type: .subscriptions),
]
```

**Load Flow**:
1. `load()` → clears state, sets `isRefreshing = true`
2. Uses `withTaskGroup` to fetch both sections in parallel
3. Calls `fetchVideos(type:api:)` for each section
4. For `.home`: calls `api.fetchHomeRows()` → gets [VideoGroup] of shelves
5. For `.subscriptions`: calls `api.fetchSubscriptions()` → gets single VideoGroup

**State**:
```swift
public struct SectionState {
    public let section: BrowseSection
    public var videos: [Video] = []       // Flattened videos from all shelves
    public var isLoading: Bool
    public var isLoadingMore: Bool
    public var nextPageToken: String?
}
```

### BrowseViewModel (`Sources/SmartTubeIOS/ViewModels/BrowseViewModel.swift`)
Full-page feed driver (mirrors Android BrowseFragment).

**Load Flow for .home**:
```swift
case .home:
    let rows = try await api.fetchHomeRows()
    videoGroups = rows  // List of shelves with layout: .row
```

**For other sections** (subscriptions, history, etc.):
```swift
case .subscriptions:
    let group = try await api.fetchSubscriptions()
    videoGroups = group.videos.isEmpty ? [] : [group]
```

## Video Rendering (UI Layer)

### HomeView (`Sources/SmartTubeIOS/Views/Home/HomeView.swift`)
- Shows chip bar at top (Home, Subscriptions, History, Playlists, Channels, optional: Shorts, Music, Gaming, News, Live, Sports)
- When `.home` section selected: displays `homeShelves` (multi-section layout)
- When other section selected: displays `sectionFeed` (full grid)

**Home Shelves Rendering**:
```swift
private var homeShelves: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(homeVM.sections) { state in
                if state.isLoading || !state.videos.isEmpty {
                    shelfView(state: state)
                }
            }
        }
    }
}

// Each shelf is a horizontal scroll:
let videos = store.settings.hideShorts ? state.videos.filter { !$0.isShort } : state.videos
ScrollView(.horizontal) {
    LazyHStack(alignment: .top, spacing: 16) {
        ForEach(videos) { video in
            VideoCardView(video: video)
                .frame(width: tvOSCardWidth)
        }
    }
}
```

### BrowseView (`Sources/SmartTubeIOS/Views/Browse/BrowseView.swift`)
Renders content in two layouts:

**Compact layout** (list):
- Row shelves displayed as horizontal ScrollView
- Grid videos displayed as vertical list with Dividers

**Grid layout** (default):
- Row shelves as horizontal ScrollView
- Grid videos arranged in 2-column grid on phone/tablet

**Shorts Filtering**:
```swift
let hideShorts = settings.settings.hideShorts
let rowGroups = vm.videoGroups.filter { $0.layout == .row }.map { g in
    guard hideShorts else { return g }
    var copy = g
    copy.videos = g.videos.filter { !$0.isShort }
    return copy
}
let gridVideos = vm.videoGroups
    .filter { $0.layout != .row }
    .flatMap(\.videos)
    .filter { !hideShorts || !$0.isShort }
```

### VideoCardView (`Sources/SmartTubeIOS/Views/Browse/VideoCardView.swift`)
- Does **NOT** visually differentiate shorts from regular videos in rendering
- Both are rendered with same layout (compact or grid)
- Shorts are distinguished only by `video.isShort` flag during filtering

## Content Type Mixing

### Current Behavior
1. **Home feed** (`fetchHomeRows`) returns mixed content: some shelves contain only regular videos, some might have shorts
   - Shorts appear as individual items mixed within regular video rows
   
2. **Shorts section** (`fetchShorts` → browse ID `"FEshorts"`) returns dedicated shorts feed
   - Browse ID: `"FEshorts"` parsed via `parseReelItemRenderer` or `parseVideoGroup`
   - Videos have `isShort: true`

3. **Settings** (`AppSettings.hideShorts`):
   - Users can toggle `hideShorts` to filter out shorts from all feeds
   - Applied during view rendering, not at API layer

4. **Home view rendering**:
   - Shelves are rendered as horizontal scrolls
   - Shorts within shelves are not visually differentiated; not auto-separated into own shelf

### No Explicit Separation
- The API doesn't separate shorts from regular videos in the home shelves
- Both types can appear mixed in the same VideoGroup
- Separation is only done if `hideShorts` is enabled in settings
- No automatic "Shorts shelf" created from mixed content

## Continuation & Pagination
- Each VideoGroup can have `nextPageToken` for pagination
- HomeViewModel stores `nextPageToken` per section for infinite scroll
- `loadMore()` fetches next page using `fetchHomeRows(continuationToken:)`
- Deduplicates based on video ID to avoid duplicates

## Architecture Summary
```
API Layer (InnerTubeAPI)
├─ fetchHomeRows() → [VideoGroup]     {rows with layout: .row}
├─ fetchSubscriptions()
├─ fetchShorts()
└─ parsing:
   ├─ parseVideoRenderer()            → isShort: reelWatchEndpoint != nil
   ├─ parseReelItemRenderer()         → isShort: true
   └─ parseTileRenderer()             → isShort: "TILE_STYLE_YTLR_SHORTS"

ViewModel Layer
├─ HomeViewModel                       {loads 2 shelves: Recommended + Subscriptions}
│  └─ fetchVideos(type:api:)
│     ├─ home: api.fetchHomeRows()
│     └─ subscriptions: api.fetchSubscriptions()
└─ BrowseViewModel                     {loads full page for any section}
   └─ fetchSection()
      ├─ home: api.fetchHomeRows()
      ├─ subscriptions: api.fetchSubscriptions()
      └─ ... other sections

View Layer
├─ HomeView                            {shows chip bar + homeShelves or sectionFeed}
│  ├─ homeShelves                      {horizontal scrolls of shelves}
│  └─ sectionFeed                      {full grid/list}
├─ BrowseView                          {alternative full-page view}
└─ VideoCardView                       {unified card rendering; no shorts-specific UI}

Filtering
└─ hideShorts: Bool                    {applied during rendering, filters $0.isShort}
```
