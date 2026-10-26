> status: implemented (2026-06)

# TOS Player — Development Worklog

macOS-only YouTube IFrame embed player (`TOSPlayerView` / `TOSPlayerViewModel`).
Activated when `Settings → Use TOS Player on Mac` is enabled.

---

## Architecture

```
MainSidebarView (RootView.swift)
  └─ store.settings.useTOSPlayerOnMac == true
       └─ TOSPlayerView
            └─ TOSPlayerViewModel
                 └─ WKWebView
                      ├─ wrapper HTML page (loadHTMLString, baseURL: example.com)
                      │    └─ <iframe src="youtube.com/embed/VIDEO_ID?...">
                      │         └─ YouTube embed player (cross-origin)
                      └─ WKUserScripts
                           ├─ webkitHiderJS  (atDocumentStart, forMainFrameOnly: false)
                           └─ stateDetectionJS (atDocumentEnd,  forMainFrameOnly: false)
```

**Why iframe wrapper?**
Loading `youtube.com/embed/...` directly as the WKWebView top-level document makes
`window.parent === window` inside the YouTube player. YouTube fires error 153 for all
videos in that configuration. Wrapping it in a `loadHTMLString` page puts the embed in
a proper `<iframe>` so `window.parent !== window`.

**Why webkitHiderJS?**
YouTube's embed player JS checks `window.webkit.messageHandlers` to detect a WKWebView
environment. When detected, it fires error 153 unconditionally regardless of cookies,
data store, or iframe setup. The hider script runs at `atDocumentStart` — before any
page JavaScript — saves the native `ytCallback` handler as `window.__nativeYTCallback`,
then redefines `window.webkit` as `undefined` so YouTube's code can't detect the
WKWebView context.

**State detection**
`stateDetectionJS` (injected `atDocumentEnd`, `forMainFrameOnly: false`) runs inside the
YouTube iframe (cross-origin, but WKWebView script injection bypasses this). It polls the
`<video>` element every 250ms, watches for `.ytp-error` overlays via MutationObserver,
and relays events to Swift via `window.__nativeYTCallback.postMessage(JSON)`.

**Communication flow**
```
YouTube iframe DOM  →  stateDetectionJS  →  window.__nativeYTCallback.postMessage()
                                          →  ScriptMessageProxy (WKScriptMessageHandler)
                                          →  TOSPlayerViewModel.handleScriptMessage()
                                          →  @Observable state + Darwin notifications
                                          →  TOSPlayerView (SwiftUI) + XCUITest
```

**Native transport overlay (2026-10)**
`controls=0` plus `TOSPlayerChromeJS` hide YouTube's in-page chrome with a
class-agnostic `visibility` hider; captions are whitelisted back in and ads are
exempted through `html.st-ad`. `TOSPlayerTransportOverlay` draws the native
chrome from the shared `PlayerControls` subviews (progress bar, icon buttons,
quick-access pills, picker sheet). `window.__stPlayerAPI` exposes quality and
audio-track over the embed's own player object; captions come from InnerTube's
`captionTracks` and render natively via `CaptionCueView` (the TV-UA embed's
captions module is not reliable). Unsupported options are hidden or disabled.
`stateDetectionJS` ticks now carry
`buffered`/`seekable`/`live`/`ad`/`rate`/`muted`. The quick-access CC pill
toggles captions (long-press opens the language picker); the more menu's
Captions row opens the same picker for track/language selection. See ADR-0010.

The bottom transport row mirrors the direct player: previous/next video buttons
that appear only for playlist-sourced videos (Current Queue with more than one
item) and always-present previous/next chapter jump buttons (disabled without
chapters or at the boundary; "previous" restarts the current chapter once >3 s
in). `TOSPlayerTransportSupport` holds the pure chapter/playlist predicates.

**Volume indicator** — the full-screen player embeds a hidden `MPVolumeView`
(`SystemVolumeControl`) to drive system volume from the edge-swipe gesture; a
side effect is that iOS suppresses its own volume HUD. `SystemVolumeMonitor`
(KVO on `AVAudioSession.outputVolume`, iOS-only) therefore drives the shared
`GestureAdjustmentHUD` for hardware-key / Control Center / route volume changes,
shown while the full-screen player is on screen.

**Ads** — the app does not hide or skip ads. If `#movie_player` has
`ad-showing`, `TOSPlayerChromeJS` disables the hider so YouTube's ad UI and
Skip Ad remain usable, and the native overlay yields.

**Fallback**
If `playerError.isFatal` (error 100/101/150/153), `TOSPlayerView` calls `onFallback()`.
`MainSidebarView` sets `tosPlayerFallbackVideoId = video.id`, which switches that video
to the standard `PlayerView`. The guard clears when a different video is opened.

---

## Key Decisions

| Decision | Reason |
|---|---|
| `loadHTMLString` wrapper instead of direct URL | Fixes `window.parent === window` self-embed detection |
| `baseURL: URL(string: "https://www.example.com")!` | Non-null cross-origin gives iframe requests proper `Referer` / `Sec-Fetch-Site: cross-site`. `nil` produces `Sec-Fetch-Site: none`, rejected by some YouTube CDN nodes. Must not be `youtube.com` (triggers self-embed detection) |
| `origin=https://www.example.com` in embed URL | Matches baseURL; signals a cross-origin third-party embed to YouTube's server |
| `webkitHiderJS` at `atDocumentStart` | Must run before YouTube's player JS, which checks `window.webkit.messageHandlers` to detect WKWebView |
| `forMainFrameOnly: false` for both scripts | Scripts must reach the YouTube `<iframe>` document; the `<video>` element is inside it |
| `didCommit` (not `didFinish`) for `navfinished` | `didFinish` waits for all subframes; the YouTube iframe may not finish if error 153 loops. `didCommit` fires as soon as the main HTML document is committed |
| `startIfNeeded()` guard (`hasStartedLoading`) | SwiftUI calls `View.init()` many times per render cycle, creating and discarding `State(initialValue:)` values. Only the instance that appears in view hierarchy calls `startIfNeeded()` |
| `#if os(macOS)` around `TOSPlayerView` in RootView | `TOSPlayerView` and `TOSPlayerViewModel` are macOS-only; iOS build would fail without the guard |
| `controls=0` + `TOSPlayerChromeJS` hider | Class-agnostic hide survives YouTube renames; captions whitelisted; ads exempted via `html.st-ad` |
| Native overlay composed from shared `PlayerControls` subviews | Visual parity with the direct player; one progress bar/pill/time-label implementation (ADR-0010) |
| `window.__stPlayerAPI` facade | The TV-UA embed does not expose the documented IFrame API; try/catch + hidden/disabled fallback |

---

## Error Codes

| Code | Name | isFatal | Meaning |
|---|---|---|---|
| 100 | video-not-found | yes | Video doesn't exist or is private |
| 101/150 | embedding-disabled | yes | Video owner has disabled embedding |
| 153 | player-config-error | yes | Environment detection (WKWebView, bad origin, etc.) |
| 2 | invalid-param | no | Bad URL parameter |
| 5 | html5-not-supported | no | Transient HTML5 player error |

---

## Test

`SmartTubeUITests/TOSPlayerUITests.swift` → `testTOSPlayerPlaysFirstHomeVideo`

Run on the macOS destination **only** (the test class is `#if os(macOS)`; running on an
iOS simulator produces 0 tests and a false "TEST SUCCEEDED"):

```bash
xcodebuild test-without-building \
  -workspace SmartTube.xcworkspace \
  -scheme SmartTube \
  -destination "id=00008132-0016591E3CFB801C" \
  -only-testing:SmartTubeUITests/TOSPlayerUITests/testTOSPlayerPlaysFirstHomeVideo \
  -resultBundlePath /tmp/tos-test-$(date +%s).xcresult
```

**Test stages verified by Darwin notifications + AX labels:**

1. Home feed loads → first video card clicked
2. `tosPlayer.closeButton` visible → player opened
3. `loadstarted` notification → `loadEmbed` called
4. `navfinished` notification → `didCommit` fired
5. `bridge` notification (×2) → stateDetectionJS running in both frames
6. `ready` notification → `<video>` element found, duration > 0
7. `tickstarted` notification → `pollVideo` loop running
8. `playing` notification → `video.paused == false`
9. `tosPlayer.stateLabel` AX label == "playing" (after 5s)
10. Close button tapped → player dismissed

---

## Worklog

### Session 1–3 (earlier)

- Built initial `TOSPlayerView` / `TOSPlayerViewModel` loading
  `https://www.youtube.com/embed/VIDEO_ID` directly in WKWebView.
- Added `stateDetectionJS` injected into the embed page to poll `<video>` state.
- Added Darwin notification bridge for XCUITest observability.

**Problem**: Error 153 fired on every load.

**Investigation**: `window.parent === window` when YouTube's embed URL is the top-level
WKWebView document. YouTube fires error 153 for self-embed context.

**Fix**: Switched to `loadHTMLString` wrapping the embed in a `<iframe>`, so
`window.parent !== window` inside YouTube's code.

**New problem**: `baseURL: URL(string: "https://www.youtube.com")!` — parent page had
youtube.com origin → YouTube detected same-origin self-embed → error 153 again.

**Fix**: `baseURL: nil` (about:blank parent origin, cross-origin, throws on access).

**New problem**: `navfinished` notification never fired — `didFinish` waited for all
subframes including the YouTube iframe, which was cancelled by error 153 loops before
finishing.

**Fix**: Moved `navfinished` notification from `didFinish` → `didCommit`.

---

### Session 4 (production debugging)

**User report**: "just tried and playing did not happen, flickering only" — production
app showed rapid error 153 reload loop even with the iframe + nil baseURL fix.

**False positive discovery**: All previous "passing" test runs were on iOS simulator
destination `6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6` (iPhone 17 Pro). Because
`TOSPlayerUITests` is `#if os(macOS)`, the test class didn't compile for iOS → 0 tests
ran → xcodebuild reported "TEST SUCCEEDED" with 0 tests.

**Correct macOS destination**: `id=00008132-0016591E3CFB801C` ("My Mac").

**Hypothesis (wrong)**: Production has YouTube auth cookies in the shared
`WKWebsiteDataStore`. YouTube fires error 153 for authenticated WKWebView sessions.
Attempted fix: `config.websiteDataStore = WKWebsiteDataStore.nonPersistent()`.

**Result**: Made things worse — error 153 fired even in the test environment (which has
no cookies). Non-persistent store is not the issue.

---

### Session 5 (root cause found + fixed — 2026-06-07)

**Audit of all xcresult bundles** (`tos-loop1/2/3`, `tos-player-test`, `tos-iframe-test`,
`tos-null-base`, `tos-nonpersist`): every single run showed the same error 153 firing
within 25–35ms of the second bridge ping. The "3/3 passing" referenced in prior notes
was the iOS simulator false positive — no run had ever genuinely passed.

**Root cause**: YouTube's embed player JavaScript checks `window.webkit.messageHandlers`
to detect a WKWebView environment. This is a native WKWebView property exposed to all
JavaScript in the `.page` content world — including YouTube's own code running inside the
`<iframe>`. When detected, YouTube fires error 153 regardless of cookies, data store,
iframe wrapper, baseURL, or any other configuration.

**Evidence**: Error fired consistently (25–35ms after iframe load) across persistent
store, non-persistent store, nil baseURL, youtube.com baseURL — the only common factor
is `window.webkit.messageHandlers` always being present in a WKWebView.

**Fix** (`TOSPlayerViewModel.swift`):

1. **Removed** `config.websiteDataStore = WKWebsiteDataStore.nonPersistent()` — wrong
   hypothesis, actively harmful.

2. **Added `webkitHiderJS`** (`atDocumentStart`, `forMainFrameOnly: false`):
   ```javascript
   var wk = window.webkit;
   window.__nativeYTCallback = wk?.messageHandlers?.ytCallback ?? null;
   Object.defineProperty(window, 'webkit', { get: () => undefined, ... });
   ```
   Runs before any page script. YouTube's code loads and checks `window.webkit` → sees
   `undefined` → no WKWebView detection → player initializes normally.

3. **Updated `stateDetectionJS`** to use `window.__nativeYTCallback` (the reference saved
   by webkitHiderJS) instead of `window.webkit.messageHandlers.ytCallback`.

4. **Changed `baseURL: nil` → `baseURL: URL(string: "https://www.example.com")!`** —
   gives the parent page a non-null cross-origin so iframe HTTP requests carry proper
   `Referer` and `Sec-Fetch-Site: cross-site` headers matching a legitimate embed.

5. **Added `origin=https://www.example.com`** to embed URL parameters, matching the
   baseURL origin.

6. **Removed deprecated `modestbranding`** parameter.

7. **Added `text` field to error messages** from stateDetectionJS so the Swift log shows
   the actual DOM text content when `.ytp-error` fires.

**Test results**: 3/3 passes on `id=00008132-0016591E3CFB801C` ("My Mac"), ~12.4s each.
All 10 test stages confirmed in device log including `playing` notification and 5s clean
playback.
