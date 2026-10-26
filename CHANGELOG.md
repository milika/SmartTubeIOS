# Changelog

All notable changes to SmartTube are documented here.

---

## [Unreleased]

### Added
- **TOS player native transport overlay** — the TOS embed now hides YouTube's own chrome (`controls=0` + class-agnostic `TOSPlayerChromeJS`) and draws the same control components as the direct player: play/pause, timeline with buffered ranges, chapter markers and SponsorBlock markers, quick-access row, plus quality/captions/audio-track pickers where the TV-UA embed's player exposes them (ADR-0010)
- Captions/audio: a quick-access CC pill in both players toggles captions on/off (long-press opens the language picker), and Captions + Audio Track rows in the more menu open pickers for track/language selection. TOS captions are rendered natively from InnerTube caption tracks (the TV-UA embed's captions module is unreliable); audio tracks come from the embed and now show localized language names where the track id exposes one. The TOS rows stay visible with a reload/empty state while tracks load.
- TOS transport: **previous/next video** buttons are now playlist-only — hidden entirely unless the video was opened from the Current Queue (a YouTube playlist, search "play all", or the Library queue), and within a queue they are enabled only when it holds more than one item (suggestions remain reachable via the swipe gesture). Added always-present **previous/next chapter** jump buttons that seek to chapter boundaries and are disabled when the video has no chapters or the playhead is at the boundary.
- TOS player: a **volume indicator** now appears when the volume changes while the full-screen player is open (hardware volume keys, Control Center, AirPods/route changes). The player embeds a hidden `MPVolumeView`, which makes iOS suppress its own system volume HUD, so the app draws its own via the shared brightness/volume HUD (`SystemVolumeMonitor`, KVO on `AVAudioSession.outputVolume`).

### Changed
- TOS playback speed now uses the shared picker sheet instead of a native `Menu`
- TOS state ticks now carry buffered/seekable ranges, live and ad flags

### Fixed
- **TOS captions were completely dead on most videos** — `fetchPlayerInfo` throws (`"Stream URLs require decryption"`) for videos whose stream URLs are cipher-protected/SABR *after* it has parsed (and discarded) the already-present caption tracks, so the TOS caption picker stayed empty and neither toggling nor language selection did anything. Captions now come from a new captions-only `InnerTubeAPI.fetchCaptionTracks(videoId:)` that ignores the stream-URL guard, and the embed fallback reads the embed's `getAudioTrack().captionTracks` (the TV embed's `getOption('captions','tracklist')` is empty)
- TOS audio-track picker now shows localized names ("English", "Deutsch") instead of "Audio 1"/"Audio 2" with a cryptic content id — the injected facade reads the embed's `getLanguageInfo()` (the only place the localized label and `langcode.number` id live) and falls back to the player response's `audioTrack.displayName`
- TOS captions: an in-flight native-caption load is now coalesced rather than dropped, so tapping CC (or Reload) while tracks are loading still turns captions on once they arrive, and the picker shows a "Loading captions…" row instead of an unexplained empty state

---

## [4.5] – 2026-06-11

### Added
- **TOS-compliant player is now the default on iOS** — playback uses an embedded YouTube IFrame player (WKWebView) with native SwiftUI controls, replacing the AVPlayer-based stream-extraction pipeline on iOS. Removes the entire class of playback failures caused by CDN/geo blocks, BotGuard/PO-token issues, and HLS/DASH manifest-parsing errors
- **Comments** added to the player's "..." overflow menu on iOS

### Changed
- Existing iOS installs are migrated automatically to the new default player; the experimental `useTOSPlayerOnIOS` toggle has been removed
- Video quality/ABR on iOS is now controlled entirely by YouTube's own player — manual quality and "max resolution" selection no longer apply on iOS
- Speed and "..." menu controls repositioned next to the back button on iOS

### Fixed
- **Mini-player** — video now keeps playing when minimized instead of stopping
- Playback speed pill stuck showing "Normal (1x)" after a speed change
- Audio occasionally cutting to silent shortly after auto-unmute
- Full-screen player no longer lingers after minimize/stop
- Safe-area inset double-counted on the back button

---

## [4.1] – 2026-05-27

### Added
- **BotGuard PO token pipeline** — complete WKWebView-based `pot=` token extraction with websafe base64 fallback; token injected into adaptive streaming requests to satisfy YouTube's enhanced bot-detection
- **AVC-only codec pinning** — "Prefer H.264" toggle in player settings pins DASH and HLS streams to AVC variants for maximum compatibility (#206)
- **Serbian & Croatian localizations** — two new languages added; 19 missing translation keys filled across all existing languages
- **HLS audio rendition proxying** — `#EXT-X-MEDIA` audio playlist URLs rewritten to `ytwebhls://` so the local proxy correctly forwards cookies to rendition segments

### Fixed
- **60 s `loadTracks` stall on SABR streams** — SABR stream detection added; `c=TVHTML5` URLs bypass the stall-prone audio-track load path (#204)
- **Dubbed audio broken via WKWebView** — HLS proxy now fetches the per-quality master URL rather than the generic master, restoring dubbed tracks (#205, #205b)
- **WKWebView cookies not forwarded to HLS proxy** — all `WKWebView` cookies, including the `googlevideo.com` domain, are now included in local proxy requests (#207)
- **8 s `loadTracks` stall** — `rqh=1` adaptive composition skipped when no `googlevideo.com` cookies are present, eliminating the hang (#208)
- **WKWebView HLS proxy silently skipped** — early `rqh=1` guard removed; proxy is now attempted regardless of cookie state at startup (#209)
- **Quality switch failed after muxed fallback** — fresh WKWebView extraction is now triggered whenever a quality change follows a muxed-only fallback (#210)
- **Stale WKWebView HLS URL used** — cached URL validity probed before constructing `AVPlayerItem`; expired URLs trigger immediate re-extraction (#211)
- **Quality button always visible** — changed from hidden-when-empty to disabled-when-empty; button remains visible but non-interactive when no quality options are available (#186)
- **Audio tracks not loaded after WKWebView HLS** — `loadAudioTracks(from:)` now called inside the `tryWebViewHLS` `readyToPlay` handler

---

## [3.0] – 2026-05-22

### Added
- **DASH adaptive quality switching** — selecting a quality tier for DASH streams rebuilds `AVMutableComposition` with the matching video track; a pending quality label is shown during the switch; the initial load is capped to the display's native resolution; VP9 variants excluded for device compatibility
- **macOS (Mac Catalyst) support** — `NSViewRepresentable` AVPlayerLayer renders in the macOS window; App Sandbox, Hardened Runtime, and `PrivacyInfo.xcprivacy` (network/API usage declarations) added; `SUPPORTED_PLATFORMS` updated; macOS build succeeds
- **TV client attestation token** — `fetchAttestationToken` injected into the TVHTML5 client authentication payload to satisfy YouTube's enhanced bot-detection for signed-in sessions
- **"Remove from Watch Later" action** — video cards inside the Watch Later playlist show a destructive remove option in the context menu; cards outside the playlist continue to show "Save to Watch Later"
- **Stats for Nerds** added to the player overflow menu on all platforms

### Fixed
- **tvOS settings tab required double-click to open** — `MainTVTabView` `TabView` now uses a selection binding; a single remote press selects the tab
- **tvOS video description and comments panels could not be closed** — `isAnyOverlayVisible` now includes both panel states so the player no longer intercepts the Menu button; each panel has its own `.focusScope` + `.onExitCommand`
- **tvOS quality preference reset to Auto on every launch** — `SettingsStore.init()` was unconditionally overwriting `preferredQuality` at startup
- **tvOS overflow menu text low contrast** — focused row highlight changed from `white.opacity(0.15)` to `gray.opacity(0.35)`
- **Playlist auto-advance not working from Search results** — `SearchView` now populates `CurrentQueueStore` before starting playback; macOS compact-grid path also fixed
- **HLS manifest cache** TTL raised from 5 min to 30 min; cache entry correctly invalidated on a 403 recovery path to prevent stale variant URLs

---

## [2.8] – 2026-05-19

### Added
- **Audio language selector in iOS fullscreen player** — speed, quality, and audio-track pill buttons in the quick-access row below the scrub bar for one-tap access without opening the overflow menu
- **tvOS player overflow menu expanded** — Captions and Audio Track rows added; Audio Only toggle available on tvOS; picker overlays no longer restricted to iOS
- **tvOS UI test coverage** — six new test suites: Settings (7 tests), Home Feed (5 tests), Library Navigation (8 tests), Player Controls (9 tests), Playback Regression (5 tests), Audio & Caption Pickers (6 tests)
- Library Subscriptions chip shortened to **"Subs"**

### Fixed
- **No audio after quality change in fullscreen** — quality-reload paths now call `loadAudioTracks(from:)` on every new `AVPlayerItem`
- **No audio when quality is not set to Auto** — audio track configuration was bypassed in manual quality selection paths
- **All audio tracks showing as "Original"** — `isOriginal` detection uses `hasMediaCharacteristic(.isMainProgramContent)` with `DEFAULT=YES` as fallback; per-track logging added
- **Caption track not remembered between videos** — last selected caption language persisted in `AppSettings` and re-applied on load
- **Captions obscuring the scrub bar** — caption overlay repositioned above the progress bar
- **Player controls hiding too quickly in fullscreen** — auto-hide timeout increased by 50%
- **Play/pause and navigation button tap targets too small** — enlarged from 44 pt to 68 pt
- **1440p quality not applied on initial load** — HLS variant fetch and `applyQualityPreference` added to all fallback entry points
- **tvOS settings missing seek-interval picker and preferred audio language selector** — `#if !os(tvOS)` guard removed from both pickers
- **tvOS long-press triggering both context menu and playback** — `onSelect` closure added to `VideoCardView`; `.onTapGesture` co-located with `.contextMenu` so the gesture arbiter suppresses playback on long-press
- **tvOS settings navigation bar hidden after scroll-down-then-up** — `.toolbar(.hidden)` guard changed from `#if os(iOS)` to `#if !os(macOS)`
- **tvOS SponsorBlock skip button not focusable** — `isSkipToastActive` gate routes focus to the skip button when a segment is detected and restores player focus on dismiss
- **Audio track selector missing from iOS overflow menu** — `moreMenuAudioTrackRow` restored (accidentally removed in a prior refactor)
- **Watch Later playlist playing videos in wrong order** — `CurrentQueueStore.replaceAll(with:)` now called before starting playback in all playlist entry points
- **Hide Shorts not filtering Subscriptions feed** — three detection gaps fixed: `parseVideoRenderer` Shorts signals, RSS feed detection via playlist enrichment, History view was incorrectly filtering non-Shorts
- **Intermittent "first video cannot be played" on launch** — stale iOS-client preload cache now invalidated before a fresh client fetch in the muxed-only fallback path
- **"Original Track" missing from tvOS preferred audio language picker**
- **Firebase network hardening**: VPN/IP-block banner suppresses "Try Again" button; Android muxed-only fallthrough no longer records a non-fatal; `NSURLError -999` (cancelled) added to transient-suppression list; request timeout raised from 20 s to 30 s

---

## [2.7] – 2026-05-16

### Added
- **Quick-access player controls** (iOS) — speed, quality, audio-track, and sleep-timer pill buttons below the scrub bar for one-tap access without opening the overflow menu
- **iCloud sync for local data** — subscriptions, watch state, current queue, and RSS feeds sync via `NSUbiquitousKeyValueStore`; opt-in toggle in Settings → General
- **Video publish date in search results** — upload age label shown in grid and compact card layouts for search results and playlist views
- **Shorts auto-pagination** — the home feed Shorts section automatically loads a second page when the initial batch is below 6 (iPhone) or 8 (tvOS)
- **Downloads screen** — Library → Downloads lists locally downloaded videos; tap to play offline, swipe to delete

### Fixed
- **OrientationManager crash on iOS 26** (EXC_BREAKPOINT, Crashlytics 1bce7ef1) — `requestGeometryUpdate` error handler was inheriting `@MainActor` isolation and invoked on a background GCD queue on iOS 26+; extracted as an explicit `nonisolated` file-scope function
- **Watch history not updating for signed-in users** — `PlaybackViewModel`'s own `InnerTubeAPI` instance was not receiving token refreshes; `WatchtimeTracker` was sending anonymous pings
- **Streaming spinner not dismissing after video loads** — `isLoading = false` moved into the `.readyToPlay` observer; audio-only path also fixed
- **App launch interrupting background audio** — premature `AVAudioSession.setActive(true)` removed from `PlaybackViewModel.init()`
- **Shorts not loading on cold launch** — `fetchShorts` and `fetchShortsMore` now use `postTV()` (TVHTML5 client) to match the TV OAuth token scope; WEB client was returning HTTP 400
- **Mini-player overlapping bottom tab bar** (iPhone portrait) — mini-player now rendered as `overlay(alignment: .bottom)` above the `TabView` safe area; `TabBarBottomInsetKey` preference captures the actual tab bar height
- **16 QPB-identified bugs**: `extractNumber` undercounting K/M/B view-count suffixes; `viewCount` always `nil` in all renderers; fallback paths (`retryWithFallbackPlayer`, `retryWith403Recovery`, `retryWithAdaptiveComposition`) dropping `playerInfo` / `availableFormats` / `availableCaptions`; `loadAsync` race on superseded tasks; `pingTrackingURL` silently discarding errors; `evictAuthSensitiveData` skipping `VideoDiskCache`; auth token captured at prefetch-task creation time (stale after refresh); `WatchtimeTracker` using stale URLs post-eviction; `phase2Task` skipped in all fallback paths; `tryLoadAudioURL` unconditionally resetting audio-only mode on any error; `itemObserverTask` race on item replacement; `endObserverTask` not restarted in audio-only mode; `parsePlaylistVideoRenderer` not implemented

---

## [2.6] – 2026-05-14

### Added
- **Safari Web Extension** — new `SafariExtension` target (`manifest.json` + `content.js`) intercepts YouTube watch, Shorts, youtu.be, and Music URLs in Safari and redirects them to `smarttube://video/<id>` without any user tap; `YouTubeLinkHandler` extended to recognise `music.youtube.com/watch?v=` URLs so the extension and the app URL handler stay in sync; `SafariExtensionURLCoverageTests` (7 tests) verify every manifest match pattern
- **Auto quality caps at display native resolution** — when `preferredQuality == .auto`, `PlaybackViewModel+Fallback.qualityCapVideoURL` now calls `displayMaxVideoHeight()` (returns `min(nativeBounds.width, nativeBounds.height)` on UIKit, 1080 on tvOS) and passes the result as `preferredMaxHeight` to `selectBestVideoFormat`; initial DASH composition and HLS `preferredMaximumResolution` hints use the same value; previously Auto unconditionally picked the highest available format regardless of screen pixel density

### Fixed
- **DASH manual quality switching broken for many videos** — `PlaybackQualityManager.reloadDASHItem` was resolving the video URL from `availableFormats` (populated by the TV auth / TVHTML5 client), whose adaptive entries use SABR-protocol URLs that `AVURLAsset.loadTracks` cannot open (AVFoundation error −11828); quality switches now resolve the video URL from `playerInfo.formats` (populated by the AndroidVR client, which returns standard CDN MPEG-4 URLs); a `selectBestVideoFormat(from:preferredMaxHeight:)` helper matches the requested quality tier to the closest available itag; the TVAuth `availableFormats` set is retained for the picker display only
- **DASH quality switch silently rebuilding at wrong resolution** — `reloadDASHItem` used `selectBestVideoFormat` without verifying the resolved height satisfied the request; when the requested tier (e.g. 480p) was absent from `playerInfo.formats`, `selectBestVideoFormat` fell back to the highest available format (e.g. 720p) and `AVMutableComposition` succeeded at that height while `selectedFormat` still reflected 480p; a `matchedFmt.height <= fmt.height` guard now rejects the fallback result and falls through to the `availableFormats` URL for proper error-recovery when the tier is absent from `playerInfo.formats`
- **Quality picker showing 144p/240p only for DASH videos** — TVAuth adaptive format entries had `height = 0` because TVHTML5 SABR responses omit the `height` field; `parseFormats` now extracts the height from the `qualityLabel` string (e.g. `"720p"` → 720) when `height == 0`, so all adaptive tiers appear correctly in the picker
- **AndroidVR client returning `LOGIN_REQUIRED` bot-detection error** — `postAndroidVR` now includes the `X-Goog-Visitor-Id` header populated from the `visitorData` field of the preceding TVAuth `/player` response; the shared `URLSession` (carrying YouTube authentication cookies from TV sign-in) is used instead of an ephemeral session; together these signals satisfy YouTube's bot-detection check for the AndroidVR client
- **Crash on age-restricted / region-locked videos** (1,048 iOS + 130 tvOS events, issue NW-3) — TV authenticated client sometimes returns a `PlayerInfo` with `hlsURL = nil` and no usable adaptive streams (muxed-only TVHTML5 URL); `PlaybackViewModel+Loading` now checks `tvInfo.hlsURL == nil && bestAdaptiveVideoURL == nil` immediately after the TV fetch and falls straight to `fetchPlayerInfoAndroid` before creating an `AVPlayerItem`, eliminating the `AVFoundationErrorDomain -11828` crash; `TVClientHLSNilFallbackTests` (8 tests) added
- **Audio-only mode silently stalling on playback start** — `tryLoadAudioURL(_:userAgent:)` now calls `setupAudioItemObserver(_:)` before `player.replaceCurrentItem(with:)`, wiring up `itemObserverTask` to catch `.failed` status (resets `isAudioOnlyMode = false` and propagates the error) and `.readyToPlay` (calls `loadAudioTracks(from:)`); previously a failed audio item had no observer and the player hung silently; `AudioOnlyModeUITests` (`testAudioOnlyModeOpensVideoWithoutError`) added
- **Mini player X button sometimes restoring fullscreen** — `fullScreenBinding` setter in `RootView` was calling `playerState.minimize()` whenever `currentVideo` cleared to `nil`; because `stop()` sets `presentation = .hidden` asynchronously, the setter raced and re-promoted state to `.miniPlayer`; setter is now a no-op (the `LandscapeFullScreenCover` UIKit coordinator already manages dismissal)
- **Audio track selection not working after fallback recovery** — `audioSelectionGroup` and `audioOptionsByID` were never refreshed when the Android fallback player, adaptive composition fallback, or 403-recovery path created a new `AVPlayerItem`; `retryWithFallbackPlayer`, `retryWithAdaptiveComposition`, and `retryWith403Recovery` in `PlaybackViewModel+Fallback` now call `loadAudioTracks(from:)` in their `.readyToPlay` observers, matching the existing pattern in the normal load and quality-change paths
- **More menu overflowing and unusable in landscape mode** (GitHub issue #45, contributor say4n) — `.frame(maxHeight: 520)` was too tall for compact vertical size class; `moreMenuOverlay` now uses 320 pt max-height in `verticalSizeClass == .compact`, adds `.safeAreaPadding(.horizontal)` plus 36 pt extra horizontal padding when landscape, keeping the menu within the live area and scrollable to the Cancel row; `player.moreMenu.scrollView` accessibility identifier added
- **"Hide Shorts" setting not filtering Shorts in Search, Library, and Channel views** (GitHub issue #41) — `AppSettings.hideShorts` was applied only in `HomeView` and `BrowseView`; `SearchView` and `LibraryView` now inject `SettingsStore` via `@Environment` and filter results before passing to `VideoGridSection`; `ChannelView.filteredVideos` extended to apply the same predicate; `RSSFeedsView.videoList` also updated for consistency; `HideShortsFilterTests` (6 tests) added
- **Audio-only mode silently stalling on playback start** — `tryLoadAudioURL(_:userAgent:)` now calls `setupAudioItemObserver(_:)` before `player.replaceCurrentItem(with:)`, wiring up `itemObserverTask` to catch `.failed` status (resets `isAudioOnlyMode = false` and propagates the error) and `.readyToPlay` (calls `loadAudioTracks(from:)`); previously a failed audio item had no observer and the player hung silently; `AudioOnlyModeUITests` (`testAudioOnlyModeOpensVideoWithoutError`) added
- **Mini player X button sometimes restoring fullscreen** — `fullScreenBinding` setter in `RootView` was calling `playerState.minimize()` whenever `currentVideo` cleared to `nil`; because `stop()` sets `presentation = .hidden` asynchronously, the setter raced and re-promoted state to `.miniPlayer`; setter is now a no-op (the `LandscapeFullScreenCover` UIKit coordinator already manages dismissal)
- **Audio track selection not working after fallback recovery** — `audioSelectionGroup` and `audioOptionsByID` were never refreshed when the Android fallback player, adaptive composition fallback, or 403-recovery path created a new `AVPlayerItem`; `retryWithFallbackPlayer`, `retryWithAdaptiveComposition`, and `retryWith403Recovery` in `PlaybackViewModel+Fallback` now call `loadAudioTracks(from:)` in their `.readyToPlay` observers, matching the existing pattern in the normal load and quality-change paths
- **More menu overflowing and unusable in landscape mode** (GitHub issue #45, contributor say4n) — `.frame(maxHeight: 520)` was too tall for compact vertical size class; `moreMenuOverlay` now uses 320 pt max-height in `verticalSizeClass == .compact`, adds `.safeAreaPadding(.horizontal)` plus 36 pt extra horizontal padding when landscape, keeping the menu within the live area and scrollable to the Cancel row; `player.moreMenu.scrollView` accessibility identifier added
- **"Hide Shorts" setting not filtering Shorts in Search, Library, and Channel views** (GitHub issue #41) — `AppSettings.hideShorts` was applied only in `HomeView` and `BrowseView`; `SearchView` and `LibraryView` now inject `SettingsStore` via `@Environment` and filter results before passing to `VideoGridSection`; `ChannelView.filteredVideos` extended to apply the same predicate; `RSSFeedsView.videoList` also updated for consistency; `HideShortsFilterTests` (6 tests) added

---

## [2.5] – 2026-05-12

### Added
- **Landscape lock button** (iOS) — rotation icon in the player top bar locks orientation in landscape; the "Landscape Always Play" toggle was removed from Settings
- **Audio-only button in player controls** (iOS) — waveform icon in the bottom player bar toggles audio-only mode; the Settings toggle was removed; tvOS retains the overflow menu row
- **Toast on mode switches** — "Audio-Only Mode" / "Video Mode" notification shown when toggling playback mode
- **DeArrow titles and thumbnails** — cached branding applied in `VideoCardView` grid and compact layouts and to `currentVideo` on load; respects the `deArrowEnabled` setting

### Fixed
- **Mini player "X" button not stopping audio** — `AVAudioSession.setActive(false)` called in `PlaybackViewModel.stop()` on dismiss
- **Overflow menu too wide and large in portrait** — `.font(.subheadline)` applied to all rows; max width constrained to 80% of screen width
- **Portrait player next/back buttons had small tap targets** — enlarged to 68 pt with circular background matching other control buttons
- **Shorts incorrectly included in playlists** — `displayVideos` filter added to `PlaylistView`
- **Video not reloading after stop and replay** — `itemObserverTask` and `endObserverTask` now cancelled in `stop()`
- **Preferred audio language ignored on AI-dubbed videos** — `DEFAULT=YES` HLS track priority corrected; device language preference evaluated before YouTube's marked default
- **Shorts visible despite "Hide Shorts" being enabled** — `parseLockupViewModel` guard relaxed to correctly detect `reelWatchEndpoint` as `isShort = true`
- **Pagination failing on transient network errors** — all 5 pagination entry points wrapped with `retryWithBackoff` (up to 3 attempts, 1–2 s exponential delay)

---

## [2.4] – 2026-05-10

### Fixed
- **Audio cutting out when manually changing video resolution** — `reloadHLSItem` and `reloadHLSItemH264Capped` in `PlaybackViewModel+Quality` created a new `AVPlayerItem` on quality switch but never called `loadAudioTracks(from:)`; `audioSelectionGroup` and `audioOptionsByID` stayed stale from the old item so `selectAudioTrack()` silently no-opped and AVPlayer fell back to muted defaults; one-line fix adds `loadAudioTracks(from: item)` in both `.readyToPlay` handlers
- **Audio quality improved to match official YouTube app** — `AVPlayerItem.audioTimePitchAlgorithm` defaulted to `.timeDomain` which introduces subtle artefacts at normal playback speeds; changed to `.spectral` in `PlaybackViewModel+Loading` when the `AVPlayerItem` is created (both HLS and adaptive paths)
- **tvOS video quality stuck at perceived ~420p despite 2160p setting** — `fetchHLSVariantURLs()` unconditionally replaced HEVC variants with H.264 for all platforms (added originally for Simulator compatibility); on tvOS HEVC is fully supported and YouTube lists it first in the manifest, so H.264 selection forced lower perceived quality; codec preference is now guarded `#if !os(tvOS)` so tvOS keeps the first (HEVC) variant while iOS/macOS still prefer H.264; `preferredPeakBitRate` hints added alongside `preferredMaximumResolution` in `reloadHLSItem` and initial load; `PlaybackQualityTests` (10 tests) added
- **Duplicate video cards causing blank cells in Home and Subscriptions feeds** — four separate deduplication gaps allowed duplicate `Video.id` values into `ForEach` arrays: (1) `fetchMoreVideos(.home)` returned `flatMap(\.videos)` with no dedup; (2) `HomeViewModel.loadMore` captured `existingIds` once before the append loop so intra-`newVideos` duplicates slipped through; (3) `BrowseViewModel.mergeIntoFirstGroup` had the same static-set gap; (4) `fetchNextPage(.home)` appended new groups without cross-group ID filtering; all four fixed with a growing-set pattern (`var seen = Set<String>(); filter { seen.insert($0.id).inserted }`); `mergedVideos` computed property gains a safety-net pass; `HomeFeedNoDuplicatesUITests` (3 tests) added
- **tvOS centre-zone double-tap and d-pad focus failures in player UI tests** — five UI tests were failing: `ToastModifier` had no accessibility identifier so toast queries raced against 2 s expiry; `ProgressView` spinner absorbed tap gestures; `SettingsStore` leaked persisted UserDefaults state between tests; SponsorBlock auto-seek disrupted player gesture tests; `testLandscapeAlwaysPlayBackButtonReturnsHome` used `guard` inside `defer` (compile-valid but never ran on error path); fixes: `.accessibilityIdentifier("player.toast")` on toast text; `.allowsHitTesting(false)` on spinner overlay; `--uitesting-reset-settings` launch-arg handler in `SettingsStore.init`; accessibility identifiers on SponsorBlock picker/NavigationLink; `testDoubleTapCentreZoneTogglesFitFill` converted from live Home feed to `--uitesting-deeplink-video=` fixed video ID to eliminate feed-timing flakiness; `guard`→`if` in defer block

---

## [2.3] – 2026-05-10

### Added
- **Shorts section on home screen** — `ShortsCardView` (portrait 9:16 thumbnail with dark gradient title overlay and duration badge) and `ShortsRowView` (horizontal `LazyHStack`, ~120 pt wide on iPhone) render above the main grid; `HomeViewModel` partitions `mergedVideos` into `homeVideos` (non-Shorts) and `homeShortsVideos` at the computed-property level with no extra network call; Shorts are identified by `Video.isShort` set at parse time from `reelWatchEndpoint`, `TILE_STYLE_YTLR_SHORTS`, or `parseReelItemRenderer`
- **Per-device YouTube recommendations setting** — `InnerTubeAPI.visitorData` (previously declared but never populated) is now extracted from `responseContext` on each browse/search response and injected into subsequent requests via `makeBody(includeVisitorData: true)`; different `visitorData` per device produces different recommendation graphs per device; toggle in Settings → Interface; disabled resets `visitorData = nil` on the next browse call

---

## [2.2] – 2026-05-06/07

### Added
- **Local Subscription Management** — follow/unfollow channels without a Google account; feeds backed by `LocalSubscriptionStore` (actor, UserDefaults persistence) and `LocalSubscriptionFeedService` (RSS fetch with InnerTube fallback); channels sorted alphabetically, feed videos sorted newest-first
- `YouTubeRSSParser` — XML-based RSS parser for YouTube channel feeds (`https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID`) using Foundation `XMLParser`; background refresh via `LocalSubscriptionFeedCache`
- **RSS Feeds feature** — users can add arbitrary YouTube channel RSS feed URLs; `RSSFeedInfo` model + `RSSFeedStore` actor (JSON in UserDefaults); `RSSFeedsViewModel` fetches all active feeds concurrently with `withTaskGroup`, deduplicates by video ID, sorts newest-first; `RSSFeedsView` (list with toolbar add button), `AddRSSFeedView` (sheet), `ManageRSSFeedsView` (delete/toggle); Share Extension detects RSS URLs and writes `pendingRSSFeedURLs` to shared UserDefaults app group for `AppEntry` to drain on launch; `RSSFeedStoreTests` unit tests
- **Audio-only playback mode** — `PlaybackViewModel+AudioOnly` provides `loadAudioOnlyItemIfEnabled()` with a three-step chain: (1) iOS-client `bestAdaptiveAudioURL` (zero extra network cost), (2) `fetchPlayerInfoAndroidVR()` using `ANDROID_VR` client (nameID 28, version 1.65.10, Oculus UA, no PO Token required), (3) silent HLS fallback with `isAudioOnlyMode = false` reset; live streams excluded; thumbnail overlay shown via `audioOnlyThumbnailOverlay` in `PlayerView+Lifecycle`; quality picker hidden in audio-only mode; "Audio Only" toggle in Settings (iOS)
- **Preferred Audio Language setting** — `Picker` in Settings → Player (iOS only) with options: System Default, English, Spanish, French, German, Japanese, Korean, Portuguese, Chinese (Simplified), Original Track; `autoSelectAudioTrack()` priority updated: saved explicit language → `"original"` sentinel selects HLS `DEFAULT=YES` track → exact language code match → prefix match (e.g. `"en"` matches `"en-US"`) → English fallback → tracks.first; `AudioTrackSelectionTests` extended (6 new tests)
- **Picture-in-Picture** (iOS) — PiP session management in `PlaybackViewModel`; toggle in Settings
- "Landscape Always Play" setting — auto-rotate to landscape when a video starts on iPhone
- **poToken groundwork** — `PoTokenProvider` protocol; `PlayerInfo.applyingPoToken(_:)` appends `&pot=<token>` to all format/HLS/DASH URLs; `InnerTubeAPI` stores `poToken`/`poTokenVideoId`/`poTokenExpiry`; `makeBody(includePoToken:)` injects `serviceIntegrityDimensions.poToken`; `ServerPoTokenProvider` (developer tool, hidden behind `poTokenServiceURL` setting) POSTs `{"videoId":"..."}` and expects `{"token":"..."}`; `PoTokenInjectionTests` (6 tests)
- **VPN "cannot play video" hardening** — `APIError.ipBlocked(String)` added; `InnerTubeAPI+Player.parsePlayerInfo` detects VPN/proxy/bot keywords in `playabilityStatus.reason` and throws `.ipBlocked` instead of `.unavailable`; `PlaybackViewModel+Loading` short-circuits the retry storm on `.ipBlocked` (one TV-auth attempt for signed-in users; Android fallback skipped); `NWPathMonitor` in `InnerTubeAPI` resets `visitorData = nil` on VPN connect/disconnect; inert "Force IPv4 (VPN users)" toggle in Settings; `CrashlyticsLogger` records `vpn_ip_block = true` non-fatal; `IPBlockDetectionTests` (12 tests)
- **VideoPreloadCache — advanced caching (Phases E–K)**:
  - *Phase E — Progressive `loadAsync`*: `loadAsync` split into Phase 1 (critical path: cache consume → `fetchPlayerInfo` retry chain → AVPlayer setup → `isLoading = false`) and Phase 2 (`.utility` Task running concurrently: SponsorBlock cache-miss fetch, `nextInfo`, `endCards`, `trackingURLs`, neighbour prefetch); `phase2Task` cancelled in `load()` and `stop()`; `ProgressiveLoadPhase2Tests` (7 tests)
  - *Phase F — Stale-while-revalidate (SWR)*: `CachedVideoData.DataType` enum (`.nextInfo`, `.endCards`, `.sponsorSegments`, `.deArrowBranding`); `staleFields: Set<DataType>` returned by `consume()`; stale values returned immediately (non-nil) while Phase 2 revalidates in background; `VideoPreloadCacheTTLTests` (16 tests)
  - *Phase G — Priority prefetch queue*: `PrefetchPriority` enum (`.speculative`, `.visible`, `.immediate`, `.userFocused`); `[PrefetchRequest]` queue bounded at 20 items; overflow evicts lowest-priority item; worker pool of 5 slots (WiFi) / 2 (cellular); `VideoCardView` passes `.visible`; neighbour prefetch passes `.speculative`; `PrefetchQueueTests` (5 tests)
  - *Phase H — In-flight coalescing*: `inFlightPlayerFetches: [String: Task<PlayerInfo?, Never>]` on `VideoPreloadCache`; `getOrFetchPlayerInfo(videoId:)` returns existing in-flight task or creates a new one; `loadAsync` coalesces against in-flight prefetch before falling to its own fetch; `InFlightCoalescingTests` (4 tests)
  - *Phase I — TTL tuning*: `nextInfoTTL` 5 min → 20 min; `sponsorTTL` 1 h → 2 h; `deArrowTTL` 1 h → 4 h; `endCardsTTL` 1 h → 4 h
  - *Phase J — Disk persistence*: `VideoDiskCache` writes `nextInfo`, `endCards`, `sponsorSegments`, `deArrowBranding` as JSON under `Caches/st-video-cache/<videoId>-<dataType>.json`; LRU eviction at 20 MB; `playerInfo` and `trackingURLs` never written (CDN/auth-sensitive); `Codable` added to `NextInfo`, `EndCard`, `EndCard.Style`, `Chapter`, `DeArrowService.BrandingInfo`; `VideoDiskCacheTests` (7 tests)
  - *Phase K — Network-aware throttling*: `NWPathMonitor` in `VideoPreloadCache`; offline → 0 workers (pauses all prefetches); cellular/constrained → 2 workers, `playerInfo`+`nextInfo`+`sponsorSegments` only; WiFi → 5 workers, all data types; `networkCap` and `allowedPrefetchDataTypes` computed properties
- `YouTubeRSSParserTests`, `LocalSubscriptionStoreTests`, `LocalSubscriptionFeedServiceTests` unit tests

### Fixed
- Shorts player section feed sometimes not visible when test starts — added explicit wait for section feed before asserting

---

## [2.1] – 2026-05-04/05

### Added
- **Landscape playback for iOS** — `OrientationManager` + `LandscapeAwareHostingController` replace SwiftUI's portrait-locked hosting controller so UIKit accepts `requestGeometryUpdate(.landscape)` while the player is on screen
- **tvOS PlayerView** (`PlayerView+tvOS`) — full d-pad navigation with `TVPlayerControl` focus model; Siri Remote play/pause, seek, menu/back handling
- **Now Playing** — lock screen and Dynamic Island metadata, artwork, and transport controls via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
- **Playback quality selection** — manual format override with `PlaybackViewModel+Quality`; HLS variant URL fetching; toast confirmation via `ToastModifier`
- **Previous/next video navigation** — history stack in `PlaybackViewModel+Navigation`; `playNext()` / `playPrevious()`
- **Caption track selection** — VTT fetch and live cue overlay in `PlaybackViewModel+Captions`
- **Sleep timer** — countdown task in `PlaybackViewModel+SleepTimer`
- **Like/Dislike actions** — `PlaybackViewModel+LikeDislike`
- **Stats for Nerds** overlay — `PlaybackViewModel+StatsForNerds`
- `PlayerView+Overlays` and `PlayerView+PickerOverlays` — player UI extracted into focused extension files
- `ToastModifier` — self-dismissing pill message (auto-clears binding after 2 s)
- `ScrollOffsetPreserver` — saves and restores LibraryView scroll position across tab switches
- `VideoDownloadUITests` — UI test for both download methods: (A) player more menu → "Download to Gallery" using `--uitesting-deeplink-video=JhCjw57u8mQ` launch arg; (B) video card long-press context menu → "Download to Gallery"; `player.moreMenu.downloadButton` accessibility identifier added to download button in `PlayerView+Overlays`
- Updated app icon (dark variant added)

### Changed
- `PlaybackViewModel` split into 14 focused extensions (Auth, AudioTracks, Captions, Controls, ControlsVisibility, Fallback, LikeDislike, Loading, Navigation, NowPlaying, Observers, Quality, SleepTimer, SponsorBlock, StatsForNerds)
- `InnerTubeAPI+VideoRenderers.swift` (~1,100 lines) split into `InnerTubeAPI+VideoGroupRows.swift` (multi-shelf home row parsing), `InnerTubeAPI+VideoRendererParsers.swift` (individual renderer parsers: `parseTileRenderer`, `parseLockupViewModel`, `parseReelItemRenderer`, `parseVideoRenderer`), and `InnerTubeAPI+VideoGroupFlat.swift` (flat video group fallback parsing); all other files kept under 1,000 lines
- Enhanced error handling and retry logic for failed stream requests
- BrowseViewModel recommended-video fetch deduplicates results
- Improved focus management for picker overlays on tvOS

### Fixed
- **Subscriptions feed not strictly sorted in chronological order** — YouTube returns each page sorted newest-first, but `BrowseViewModel.mergeIntoFirstGroup` and `HomeViewModel.loadMore` appended pages without global re-sort, so videos from page 2 appeared out of position relative to page 1; `videoGroups[0].videos` is now re-sorted by `publishedAt` descending after each `mergeIntoFirstGroup` call (subscriptions case) and after each `loadMore` append in `HomeViewModel`; `SubscriptionsSortTests` (pagination merge test) added

---

## [2.0] – 2026-05-03/04

### Added
- **Localisation** — `Localizable.xcstrings` string catalog covering the full app
- `InnerTubeAPIProtocol` — protocol abstraction over `InnerTubeAPI` enabling mock injection in tests
- `ViewModelLogger` — structured per-category logging routed to Crashlytics
- Sign-in UI: one-tap "Open Activation Page" button (opens pre-filled URL); "Or scan from another device" QR divider section
- Sign-in progress guard in `AuthService` — prevents concurrent device-code flows
- Comprehensive unit tests: `WebVTTParserTests`, `VideoStateStoreTests`, `ViewModelTests`, `VideoPreloadCacheTTLTests`, `SearchFilterUITests`, `YouTubeLinkHandlerTests`
- UI test suites: Channel, Library (History / Playlists / Subscriptions), Player controls, Recommended chip pagination, Search, Settings, Shorts, Audio track selection
- GitHub issue templates (bug report, feature request)

### Changed
- Updated Privacy Policy
- Various internal refactors for readability and maintainability

### Fixed
- **Login failures requiring multiple retries on iPhone** — `AuthService` gained `retryWithBackoff<T>()`: up to 3 attempts with 1–10 s exponential delay on transient `URLError` codes (timeout, connection lost, offline, SSL); `requestDeviceCode`, `fetchUserInfo`, `validAccessToken`, `refreshAccessToken` all wrapped; permanent OAuth errors (`invalid_grant`, `invalid_client`, `unauthorized_client`) are still propagated immediately without retry; `YouTubeClientCredentialsFetcher.fetchFromYouTube` retries twice before falling back to hardcoded credentials; `URLSession` in `InnerTubeAPI.init` now uses `waitsForConnectivity = true`, 20 s request timeout, 60 s resource timeout
- **SponsorBlock causing video playback to stall** — race condition between time observer ticks and async seek callback; debounce guard (`sponsorSkipDebounceTask`) prevents redundant seeks when multiple ticks fire on the same segment; seek-in-flight guard skips sponsor check while a seek is pending; exact seek (tolerance = zero) used for segment endpoints instead of fuzzy tolerance; segment-near-end threshold widened from 0.5 s to 2.0 s of video duration to prevent clamping to last frame; buffer-status verification logs warning when player is `.waiting` for >2 s after seek
- **Subscriptions feed showing videos out of chronological order** — `InnerTubeAPI+Browse.fetchSubscriptions()` now sorts each page's videos by `publishedAt` descending on arrival; `parseGuideChannels()` and `parseSubscribedChannels()` now sort channels alphabetically, matching `LocalSubscriptionStore`'s existing order
- **Apple TV fast-forward and rewind buttons showing white squares and not responding** — SF Symbol images in `seekButton` and `playPauseButton` rendered as white-on-white on tvOS focus engine due to `scaleEffect` + `shadow` + `buttonStyle(.plain)` interaction; fixed with `.renderingMode(.original)` + `.foregroundStyle(.white)`; reduced shadow intensity; Siri Remote gen 1 edge-tap left/right swipe gestures wired to `seekRelative` when controls are visible
- **Audio track language defaulting to wrong language for AI-dubbed videos** — when no `DEFAULT=YES` track is present in the HLS manifest, `index == 0` was incorrectly marked `isOriginal = true`; for AI-dubbed videos YouTube often lists the dubbed track first, causing the wrong track to be auto-selected; `isOriginal` is now only set when `group.defaultOption == option` (explicit HLS `DEFAULT=YES`); auto-selection waterfall reordered: (1) user's saved language preference, (2) HLS `DEFAULT=YES` original, (3) English track, (4) device locale, (5) first track
- **Videos unable to play / "reload page" error on iOS 18.7.2 and iOS 26** — hardcoded `"iOS 18_3_2"` User-Agent and client version string caused YouTube to detect a version mismatch on newer OS versions and return `UNPLAYABLE` or cipher-protected streams; User-Agent now uses `UIDevice.systemVersion` dynamically; SponsorBlock segment fetch moved to a detached background `Task` after `AVPlayerItem` is `.readyToPlay` so it no longer blocks stream setup on slow connections

---

## [1.9] – 2026-05-02

### Added
- Home feed staleness check — `HomeViewModel.refreshIfStale(threshold:)` reloads shelves when content is older than 15 minutes
- `InnerTubeAPI`: authenticated playback tracking URLs (`fetchAuthenticatedTrackingURLs`), TV-client endpoint (`postTV`), section-date and relative-date parsing
- Home feed fallback to popular videos when watch history is empty

### Changed
- HomeView replaced shelf rows with `VideoGridSection` grid layout
- `VideoCardView` layout and thumbnail improvements

---

## [1.8] – 2026-05-01

### Added
- Android-client HLS fallback in `PlaybackViewModel` — retries with Android credentials when the iOS HLS manifest returns a 404 due to IP-binding; last attempted URL stamped into Crashlytics non-fatal reports
- `VideoPlaybackRegressionUITests` — UI test coverage for core playback flows

### Changed
- `VideoPreloadCache` keeps its `InnerTubeAPI` access-token in sync with the signed-in session

---

## [1.7] – 2026-04-30

### Added
- `VideoPreloadCache` — background prefetch and cache of video stream data keyed by video ID
- `WatchtimeTracker` — reports playback position metrics to YouTube's watchtime endpoint
- `InnerTubeAPIKey` SwiftUI environment key — all views receive `InnerTubeAPI` via `@Environment(\.innerTubeAPI)` instead of constructor injection

### Changed
- Updated InnerTube client version strings

---

## [1.6] – 2026-04-28/29 — Initial Open Source Release

### Added
- Initial open source release of SmartTube for iPhone, iPad, macOS, and Apple TV
- **Audio track selection** — loads alternate HLS renditions (dubbed/translated tracks) from the manifest; auto-selects by device locale; persisted in `AppSettings`
- tvOS d-pad navigation in the player — custom `TVPlayerControl` enum; directional seek, play/pause, and back without SwiftUI focus engine
- tvOS Settings: Ko-fi and GitHub QR code sheets
- Firebase dSYM copy script for crash symbolication
- `CrashlyticsLogger` integration

### Changed
- `AuthService`: concurrent sign-in guard; automatic sign-out on permanent OAuth failures (`invalid_grant`, `invalid_client`, `unauthorized_client`); device code expiration clamped at server-reported `expiresIn`
- `VideoDownloadService` download-session and background-task code restricted to iOS with `#if os(iOS)` guards
- `PlaybackViewModel`: foreground/background audio session handling (`handleForeground()` / `handleBackground()`)
