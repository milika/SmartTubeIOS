> status: implemented (2026-06)

# TOS Player → iOS — Deep Analysis & Implementation Plan

Porting the TOS-compliant YouTube IFrame player (`TOSPlayerView` / `TOSPlayerViewModel`)
from macOS to iOS. All TOS files are currently guarded by `#if os(macOS)`. This document
catalogues every delta between the two platforms, defines the target architecture, and
lists the concrete implementation tasks.

---

## 1. What We're Porting

Six Swift files compose the TOS player today (all `#if os(macOS)`):

| File | Purpose |
|------|---------|
| `TOSPlayerViewModel.swift` | WKWebView setup, JS inject, state machine, JS commands |
| `TOSPlayerViewModel+WebBridge.swift` | `handleScriptMessage` — JS↔Swift bridge |
| `TOSPlayerViewModel+SponsorBlock.swift` | Segment fetch, tick-driven skip/toast logic |
| `TOSPlayerViewModel+LikeDislike.swift` | Like/dislike InnerTubeAPI calls |
| `TOSPlayerViewModel+SleepTimer.swift` | Sleep timer countdown |
| `TOSPlayerViewModel+WatchHistory.swift` | Watch-position checkpoint + history |
| `TOSPlayerView.swift` | SwiftUI view — WKWebView host, top-right menus, SponsorBlock toast |

The JS bridge, SponsorBlock logic, like/dislike, sleep timer, and watch history are all
**purely API/timer/WKWebView operations with no platform-specific code** — they port by
removing the `#if os(macOS)` guard and nothing else.

The VM core and the view both have **platform-specific deltas** catalogued below.

---

## 2. Platform Delta Catalogue

### 2a. macOS-only APIs in the ViewModel

| Line | macOS API | iOS replacement |
|------|-----------|----------------|
| `TOSPlayerViewModel.swift:212` | `webView.setValue(false, forKey: "drawsBackground")` | `webView.isOpaque = false` + `webView.backgroundColor = .clear` + `webView.scrollView.backgroundColor = .clear` |
| All Darwin notifications (`CFNotificationCenterPostNotification`) | Available on iOS too — no change needed |

### 2b. WKWebView config differences

On iOS, two additional flags are **mandatory**:

```swift
// Without this, YouTube's embed tries to launch the native iOS video player
// when the user taps play — overrides in-page video entirely.
config.allowsInlineMediaPlayback = true

// Nice-to-have: allows AirPlay from the WKWebView.
config.allowsAirPlayForMediaPlayback = true
```

`mediaTypesRequiringUserActionForPlayback = []` already works on iOS — no change.

The embed URL already includes `playsinline=1` — required on iOS to keep the video
inside the WKWebView frame rather than going native-fullscreen.

### 2c. View — dismissal & back button

| macOS | iOS |
|-------|-----|
| `onExitCommand` (Esc key) | No equivalent — needs a real back button |
| No visible back button (every placement conflicted with OS titlebar chrome) | Full-screen modal — OS chrome is not present, back button is safe and expected |
| `browseVM.deepLinkedVideo = nil; dismiss()` | `tosState.minimize()` (mini-player) |

**Key difference**: on macOS, the TOS player is a ZStack overlay *inside* the
NavigationSplitView content area, so the macOS window's traffic-light + back-chevron OS
chrome floats above it. On iOS, it is a full-screen modal (`.fullScreenCover`) — no OS
chrome at all. A back button is straightforward.

### 2d. View — top-right control cluster

The macOS TOS player uses native `Menu` buttons (speed picker, more menu) because
controls:1 leaves no native affordance for custom overlay pickers. On iOS the same
native `Menu` approach works identically — `menuStyle(.borderlessButton)` on iOS
renders as a contextual menu, which is the idiomatic iOS equivalent.

### 2e. Orientation

The iOS TOS player is presented via `LandscapeAwareHostingController` (the same
UIKit wrapper used for standard `PlayerView`). `OrientationManager.shared.playerIsActive`
must be set `true`/`false` in `onAppear`/`onDisappear` to unlock landscape rotation,
mirroring what `PlayerView+Lifecycle.swift` already does.

### 2f. Mini-player (audio continuity after dismiss)

**Decision: mini-player with audio continuity.**

On macOS there is no mini-player. On iOS the standard AVPlayer has a mini-player bar
(`PlayerStateStore` + `MiniPlayerView`). The TOS player cannot share `PlayerStateStore`
(which is tightly coupled to AVPlayer / `PlaybackViewModel`). The approach is a parallel
`TOSPlayerStateStore` — see §3 below.

### 2g. Presentation entry point

| macOS | iOS |
|-------|-----|
| `MainSidebarView`: ZStack overlay driven by `browseVM.deepLinkedVideo` | `MainTabView.onChange(of: browseVM.deepLinkedVideo)` currently calls `playerState.play(video:)` → AVPlayer |
| HomeView: `navigationDestination` if `useTOSPlayerOnMac` | HomeView: `playerState.play(video:)` always |

On iOS we intercept `browseVM.deepLinkedVideo` in `MainTabView.onChange` (and the same
`browseVM.deepLinkedVideo` path in RootView's deeplink handler) and route to
`TOSPlayerStateStore.play(video:)` instead of `PlayerStateStore.play(video:)`.

### 2h. Settings flag

`AppSettings.useTOSPlayerOnMac` is explicitly documented as having no effect on iOS/tvOS.
We add a parallel `useTOSPlayerOnIOS: Bool` (default: `false`, opt-in experiment) and a
new "Experimental (iOS)" section in `SettingsView`.

---

## 3. Target Architecture (iOS)

```
AppEntry
  ├─ @Environment(PlayerStateStore.self)     ← existing AVPlayer state
  └─ @Environment(TOSPlayerStateStore.self)  ← NEW: TOS player state

MainTabView
  ├─ .onChange(of: browseVM.deepLinkedVideo) {
  │     if useTOSPlayerOnIOS && !fallback → tosState.play(video:)
  │     else                              → playerState.play(video:)  (existing)
  │  }
  ├─ .landscapePlayerCover(item: tosFullScreenBinding) { TOSPlayerView(...) }
  │     (presented when tosState.presentation == .fullScreen)
  └─ .overlay(alignment: .bottom) {
        if tosState.presentation == .miniPlayer { TOSMiniPlayerView() }
        else if playerState.presentation == .miniPlayer { MiniPlayerView() }  (existing)
     }
```

### TOSPlayerStateStore (new, `#if os(iOS)`)

Mirrors `PlayerStateStore` but owns `TOSPlayerViewModel` (WKWebView) instead of
`PlaybackViewModel` (AVPlayer).

```swift
@MainActor @Observable
final class TOSPlayerStateStore {
    enum Presentation { case hidden, miniPlayer, fullScreen }

    private(set) var presentation: Presentation = .hidden
    private(set) var currentVideo: Video?
    private(set) var vm: TOSPlayerViewModel?

    /// Per-video fallback guard (mirrors macOS tosPlayerFallbackVideoId).
    private(set) var fallbackVideoId: String?

    func play(video: Video, api: InnerTubeAPI)
    func minimize()   // → .miniPlayer, WKWebView keeps playing
    func expand()     // → .fullScreen
    func stop()       // vm.pause(); vm.saveProgress(); vm = nil; .hidden
    func markFallback(videoId: String)  // embeddingDisabled / notFound → AVPlayer fallback
}
```

**Why `vm` is Optional here**: when `stop()` is called the WKWebView is released
(playback fully stops). On `play(video:)` a fresh `TOSPlayerViewModel` is created.
Between `minimize()` and `expand()` the VM lives on — the WKWebView keeps running
inside `TOSPlayerStateStore` even though `TOSPlayerView` has been dismissed.

### TOSPlayerView on iOS

```swift
// Dismissal: back button and swipe-down both call tosState.minimize()
Button { tosState.minimize() } label: {
    Image(systemName: AppSymbol.chevronLeft)
        .font(.title2)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.4))
        .clipShape(Circle())
}
.accessibilityIdentifier("tosPlayer.backButton")
.padding(.top, geo.safeAreaInsets.top + 8)
.padding(.leading, 16)
```

The back button is safe on iOS — full-screen modal has no OS chrome above it.

`onDisappear` still calls `vm.pause()` + `vm.saveProgress()` — BUT we only call
`vm.pause()` when `tosState.presentation == .hidden` (full stop), not when
`tosState.presentation == .miniPlayer` (audio should continue). This is handled by
`TOSPlayerStateStore.minimize()` NOT calling `vm.pause()`.

### TOSMiniPlayerView (new, `#if os(iOS)`)

```
[ ▶/⏸ ]  [ thumbnail ]  Video title…  [ ✕ ]
```

- Tap play/pause → `tosState.vm?.pause()` / `tosState.vm?.play()`
- Tap anywhere (title/thumbnail area) → `tosState.expand()`
- Tap ✕ → `tosState.stop()`
- Positioned above the tab bar, same as `MiniPlayerView`
- Only shown when `tosState.presentation == .miniPlayer`

### Conflict: AVPlayer mini-player vs TOS mini-player

Both cannot be shown simultaneously. Rules:

| Action | Effect |
|--------|--------|
| User starts TOS video while AVPlayer mini-player active | `playerState.stop()` then `tosState.play(video:)` |
| User starts AVPlayer video while TOS mini-player active | `tosState.stop()` then `playerState.play(video:)` |
| User dismisses TOS player (back) | `tosState.minimize()` — TOS mini-player appears |
| User taps ✕ on TOS mini-player | `tosState.stop()` |
| User taps on TOS mini-player | `tosState.expand()` |

Implementation: `MainTabView.onChange(of: browseVM.deepLinkedVideo)` stops the other
player before starting the new one.

---

## 4. Implementation Tasks

Tasks in dependency order. Each can be implemented and committed independently.

---

### Task 1 — `AppSettings`: add `useTOSPlayerOnIOS`

**File**: `SmartTubeIOS/Sources/SmartTubeIOSCore/AppSettings.swift`

1. Add `public var useTOSPlayerOnIOS: Bool` under the Experimental section (near line 153).
2. Set default `false` in both `macOS` and `iOS` default factories (`defaultsMac` / `defaultsIOS`).
3. Add `.useTOSPlayerOnIOS` to the `CodingKeys` enum.
4. Add decode line: `useTOSPlayerOnIOS = c.safeDecode(Bool.self, forKey: .useTOSPlayerOnIOS, default: d.useTOSPlayerOnIOS)`.

**Acceptance**: `AppSettings()` compiles on both platforms; `store.settings.useTOSPlayerOnIOS` is accessible.

---

### Task 2 — Remove `#if os(macOS)` guards from all TOS files

**Files** (all six extension files + view + view model):

Replace the outer `#if os(macOS)` / `#endif // os(macOS)` guard with `#if !os(tvOS)`.

Files:
- `TOSPlayerViewModel.swift`
- `TOSPlayerViewModel+WebBridge.swift`
- `TOSPlayerViewModel+SponsorBlock.swift`
- `TOSPlayerViewModel+LikeDislike.swift`
- `TOSPlayerViewModel+SleepTimer.swift`
- `TOSPlayerViewModel+WatchHistory.swift`
- `TOSPlayerView.swift`

**Acceptance**: project builds on macOS (no regression) and the files are now parsed on iOS.

---

### Task 3 — `TOSPlayerViewModel`: fix iOS-specific WKWebView setup

**File**: `TOSPlayerViewModel.swift`

Inside `init`, after `WKWebView(frame: .zero, configuration: config)`:

```swift
#if os(macOS)
self.webView.setValue(false, forKey: "drawsBackground")
#else
self.webView.isOpaque = false
self.webView.backgroundColor = .clear
self.webView.scrollView.backgroundColor = .clear
#endif
```

Inside `init`, when building `WKWebViewConfiguration`:

```swift
#if os(iOS)
config.allowsInlineMediaPlayback = true
config.allowsAirPlayForMediaPlayback = true
#endif
```

**Acceptance**: builds on iOS without runtime crashes or white-flash behind the WKWebView.

---

### Task 4 — `TOSPlayerStateStore` (new iOS file)

**New file**: `SmartTubeIOS/Sources/SmartTubeIOS/TOSPlayerStateStore.swift`

Full implementation as described in §3. Key points:

- `#if os(iOS)` guard
- `@MainActor @Observable final class TOSPlayerStateStore`
- Owns `private(set) var vm: TOSPlayerViewModel?` — created in `play(video:)`, released in `stop()`
- `minimize()` does NOT call `vm.pause()` — audio continues
- `stop()` calls `vm.pause(); vm.saveProgress(); vm = nil`
- `markFallback(videoId:)` stores the fallback ID for the current session

---

### Task 5 — `TOSPlayerView`: add iOS back button and iOS dismissal

**File**: `TOSPlayerView.swift`

Inside the `GeometryReader { geo in ZStack(alignment: .topLeading) {` body:

```swift
#if os(iOS)
// Back button — top-left, safe on iOS (no OS titlebar chrome above the modal).
// Calls tosState.minimize() so audio continues in the mini-player.
// No onExitCommand (Esc) on iOS.
backButton(topInset: geo.safeAreaInsets.top)
#endif
```

Add `backButton(topInset:)` private func (iOS only):

```swift
#if os(iOS)
@Environment(TOSPlayerStateStore.self) private var tosState

private func backButton(topInset: CGFloat) -> some View {
    VStack {
        HStack {
            Button { tosState.minimize() } label: {
                Image(systemName: AppSymbol.chevronLeft)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("tosPlayer.backButton")
            .padding(.top, topInset + 8)
            .padding(.leading, 16)
            Spacer()
        }
        Spacer()
    }
}
#endif
```

Replace `onExitCommand` with platform-conditional:

```swift
#if os(macOS)
.onExitCommand {
    browseVM.deepLinkedVideo = nil
    dismiss()
}
#endif
```

Update `onDisappear` — only pause when actually stopping (not minimizing):

```swift
.onDisappear {
    #if os(iOS)
    // On iOS, onDisappear fires both on minimize (→ mini-player, audio should continue)
    // and on full stop. TOSPlayerStateStore.stop() calls vm.pause() explicitly for the
    // full-stop case; here we only act if presentation is .hidden (full dismiss).
    guard tosState.presentation == .hidden else { return }
    #endif
    tosLog.notice("[TOSPlayerView] onDisappear …")
    vm.pause()
    vm.saveProgress()
}
```

**Note on vm ownership on iOS**: `TOSPlayerView` on iOS reads `vm` from
`@Environment(TOSPlayerStateStore.self).vm` rather than a `@State`. The `@State vm`
stays macOS-only. On iOS the view is stateless — the store owns the vm.

---

### Task 6 — `TOSMiniPlayerView` (new iOS file)

**New file**: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/TOSMiniPlayerView.swift`

```swift
#if os(iOS)
import SwiftUI
import SmartTubeIOSCore

struct TOSMiniPlayerView: View {
    @Environment(TOSPlayerStateStore.self) private var tosState

    var body: some View {
        HStack(spacing: 12) {
            // Play/pause
            Button {
                if tosState.vm?.playerState == .playing {
                    tosState.vm?.pause()
                } else {
                    tosState.vm?.play()
                }
            } label: {
                Image(systemName: tosState.vm?.playerState == .playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.playPauseButton")

            // Thumbnail + title — tap to expand
            Button { tosState.expand() } label: {
                HStack(spacing: 10) {
                    if let thumb = tosState.currentVideo?.thumbnailURL {
                        AsyncImage(url: thumb) { img in img.resizable().scaledToFill() }
                            placeholder: { Color.gray.opacity(0.3) }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(tosState.currentVideo?.title ?? "")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.expandButton")

            // Dismiss
            Button { tosState.stop() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.closeButton")
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(.regularMaterial)
        .accessibilityIdentifier("tosPlayer.miniPlayerBar")
    }
}
#endif
```

---

### Task 7 — Wire `TOSPlayerStateStore` into `AppEntry` and `MainTabView`

**Files**: `AppEntry.swift` (or wherever `PlayerStateStore` is created), `RootView.swift`

1. Create `TOSPlayerStateStore` at the same level as `PlayerStateStore`:
   ```swift
   #if os(iOS)
   @State private var tosPlayerState = TOSPlayerStateStore()
   #endif
   ```
   Inject as `.environment(tosPlayerState)` everywhere `PlayerStateStore` is injected.

2. In `MainTabView.body`, intercept `browseVM.deepLinkedVideo`:

   ```swift
   .onChange(of: browseVM.deepLinkedVideo) { _, video in
       guard let video else { return }
   #if os(iOS)
       if store.settings.useTOSPlayerOnIOS && tosState.fallbackVideoId != video.id {
           // Stop AVPlayer mini-player if active
           if playerState.presentation != .hidden { playerState.stop() }
           tosState.play(video: video, api: api)
           browseVM.deepLinkedVideo = nil
           return
       }
   #endif
       // Existing AVPlayer path
       playerState.play(video: video)
       browseVM.deepLinkedVideo = nil
   }
   ```

3. Add `TOSPlayerView` full-screen cover in `MainTabView`:

   ```swift
   #if os(iOS)
   .landscapePlayerCover(item: tosFullScreenBinding) { video in
       TOSPlayerView(video: video, api: api) {
           // Embedding-disabled fallback
           tosState.markFallback(videoId: video.id)
           tosState.stop()
           playerState.play(video: video)
       }
       .environment(store)
       .environment(tosState)
   }
   #endif
   ```

   Where `tosFullScreenBinding` is:
   ```swift
   let tosFullScreenBinding = Binding<Video?>(
       get: { tosState.presentation == .fullScreen ? tosState.currentVideo : nil },
       set: { if $0 == nil { tosState.minimize() } }
   )
   ```

4. Add `TOSMiniPlayerView` to the mini-player overlay in `MainTabView`:

   ```swift
   #if os(iOS)
   .overlay(alignment: .bottom) {
       VStack(spacing: 0) {
           if tosState.presentation == .miniPlayer {
               TOSMiniPlayerView()
                   .transition(.move(edge: .bottom).combined(with: .opacity))
           } else if playerState.presentation == .miniPlayer {
               MiniPlayerView()  // existing
                   .transition(.move(edge: .bottom).combined(with: .opacity))
           }
           Color.clear.frame(height: tabBarBottomInset).allowsHitTesting(false)
       }
       .animation(.easeInOut(duration: 0.2), value: tosState.presentation)
   }
   #endif
   ```

5. Add safe-area inset spacer when TOS mini-player is active (mirrors the existing one for AVPlayer):

   ```swift
   #if os(iOS)
   .safeAreaInset(edge: .bottom, spacing: 0) {
       if tosState.presentation == .miniPlayer || playerState.presentation == .miniPlayer {
           Color.clear.frame(height: 62)
       }
   }
   #endif
   ```

---

### Task 8 — `SettingsView`: add iOS experimental section

**File**: `SettingsView.swift`

Add alongside the existing `#if os(macOS) private var experimentalSection`:

```swift
#if os(iOS)
private var experimentalSection: some View {
    @Bindable var store = store
    return Section {
        Toggle("IFrame Player (TOS-compliant, shows ads)", isOn: $store.settings.useTOSPlayerOnIOS)
            .accessibilityIdentifier("settings.useTOSPlayerOnIOSToggle")
    } header: {
        Text("Experimental")
    } footer: {
        Text("Uses YouTube's official embedded player. Quality selection and downloads are unavailable. Ads will play. Useful for videos that refuse to play via the standard path.")
    }
}
#endif
```

Add `experimentalSection` call to the iOS `body` (same position as on macOS, near the bottom of the list).

---

### Task 9 — Update doc comments and `AppSettings` comment

**File**: `AppSettings.swift`, comment on `useTOSPlayerOnMac`:

```swift
/// Opt-in experiment — has no effect on tvOS.
public var useTOSPlayerOnMac: Bool
```

Remove the "(has no effect on iOS)" clause since iOS now has its own flag.

**File**: `TOSPlayerView.swift` header comment — update the `Entry path:` block:

```
// Entry path (macOS):
//   MainSidebarView → store.settings.useTOSPlayerOnMac → TOSPlayerView
//
// Entry path (iOS):
//   MainTabView.onChange(of: browseVM.deepLinkedVideo)
//     → store.settings.useTOSPlayerOnIOS
//       → TOSPlayerStateStore.play(video:) → .landscapePlayerCover → TOSPlayerView
```

---

### Task 10 — UI Tests (`TOSPlayerIOSUITests.swift`)

**New file**: `SmartTubeApp/UITests/TOSPlayerIOSUITests.swift`

Minimal test suite for the iOS TOS player. Mirrors `TOSPlayerUITests.swift` in structure:
- `testTOSPlayerIOSSmoke` — opens first home video via TOS player, verifies `tosPlayer.stateLabel` appears with "playing", back button tap → stateLabel disappears (mini-player), mini-player bar appears
- `testTOSPlayerIOSStopsAudioOnStop` — opens, minimizes (mini-player appears), taps ✕ → mini-player disappears, `vm.pause()` was called (log evidence: `[pause] pauseAllMediaPlayback completed`)

Uses the same `AGENT-POST-RUN-CHECK: ui-tests-with-logs` marker pattern.

**Darwin notifications on iOS**: `CFNotificationCenterPostNotification` is available on iOS
(it is a CoreFoundation API, not macOS-only). The same notification names used in
`TOSPlayerViewModel+SponsorBlock.swift` et al. will fire on iOS — XCUITest can `wait(for:)`
them using `XCTDarwinNotificationExpectation`.

---

## 5. Known Risks & Open Questions

### 5a. WKWebView autoplay on iOS — muted-autoplay dance
The `stateDetectionJS` already handles the muted-start / auto-unmute flow (plays muted,
waits for `t > 0.1`, then unmutes). This was originally motivated by WebKit's autoplay
policy, which is the same on iOS — so the behaviour should transfer without change.
However, iOS WebKit may be stricter in some cases (e.g. without a recent user gesture at
the UIViewController level). **Verify**: first run of `testTOSPlayerIOSSmoke` is the
empirical test — if `autoUnmuted` log line fires, the autoplay dance works.

### 5b. YouTube IFrame inline vs native fullscreen on iOS
`playsinline=1` in the embed URL + `config.allowsInlineMediaPlayback = true` should keep
the embed in-page. If YouTube's own controls include a fullscreen button that launches
native UIKit fullscreen, the player UI disappears and we lose control. This is an existing
known limitation of `controls:1` on iOS WebKit — no fix exists short of switching to
`controls:0` and building our own control layer. (Implemented 2026-10 — see ADR-0010:
`controls:0` + `TOSPlayerChromeJS` + `TOSPlayerTransportOverlay` composed from the shared
`PlayerControls` subviews.)

### 5c. Background audio
WKWebView audio on iOS is subject to `AVAudioSession` category. The existing app's session
is configured for `AVAudioSession.Category.playback`, which also covers WKWebView media
in the same process. When minimized to mini-player, the WKWebView's audio should continue.
When the app is backgrounded while TOS mini-player is active, iOS may suspend the WKWebView
process — this needs verification. If audio stops on background, `scenePhase == .background`
handling will need to call `webView.resumeAllMediaPlayback()` on foreground (analogous to
`handleForeground()` in `PlaybackViewModel`).

### 5d. `TOSPlayerView` vm ownership on iOS
On macOS, `TOSPlayerView` owns `@State var vm: TOSPlayerViewModel`. On iOS, `vm` must
live in `TOSPlayerStateStore` to survive the view being dismissed to mini-player. The
view therefore has a split ownership model: `@State vm` on macOS, env-injected on iOS.
This is the most architecturally disruptive change — careful platform-conditional
initialization in `TOSPlayerView.init` is required.

Proposed:
```swift
#if os(macOS)
@State private var vm: TOSPlayerViewModel
#else
@Environment(TOSPlayerStateStore.self) private var tosState
private var vm: TOSPlayerViewModel { tosState.vm! }
#endif
```

The iOS `vm` force-unwrap is safe because `TOSPlayerView` is only ever presented when
`tosState.presentation == .fullScreen` and `tosState.vm != nil`.

### 5e. Fallback flow on iOS
macOS has two fallback sites (`MainSidebarView` + `HomeView`). On iOS the single intercept
is in `MainTabView.onChange(of: browseVM.deepLinkedVideo)`. On embedding error, the
`onFallback` closure calls `tosState.markFallback(videoId:)` + `tosState.stop()` +
`playerState.play(video:)`. This is a cleaner single-site fallback than macOS.

---

## 6. File Change Summary

| File | Change |
|------|--------|
| `AppSettings.swift` | Add `useTOSPlayerOnIOS: Bool` (Task 1) |
| `TOSPlayerViewModel.swift` | `#if os(macOS)` → `#if !os(tvOS)`; iOS WKWebView fixes (Tasks 2, 3) |
| `TOSPlayerViewModel+WebBridge.swift` | Guard change only (Task 2) |
| `TOSPlayerViewModel+SponsorBlock.swift` | Guard change only (Task 2) |
| `TOSPlayerViewModel+LikeDislike.swift` | Guard change only (Task 2) |
| `TOSPlayerViewModel+SleepTimer.swift` | Guard change only (Task 2) |
| `TOSPlayerViewModel+WatchHistory.swift` | Guard change only (Task 2) |
| `TOSPlayerView.swift` | Guard change; iOS back button; iOS dismissal; vm ownership (Tasks 2, 5) |
| `TOSPlayerStateStore.swift` | **New file** — iOS TOS player state (Task 4) |
| `TOSMiniPlayerView.swift` | **New file** — iOS mini-player UI (Task 6) |
| `AppEntry.swift` / `RootView.swift` | Inject `TOSPlayerStateStore` (Task 7) |
| `RootView.swift` (`MainTabView`) | Intercept deeplink, cover, mini-player overlay (Task 7) |
| `SettingsView.swift` | iOS experimental section (Task 8) |
| `TOSPlayerIOSUITests.swift` | **New file** — iOS smoke + pause tests (Task 10) |

**Estimated task ordering** (maximize safety, minimize merge conflicts):
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

Tasks 1–3 are purely additive / guard changes — zero risk to the macOS build.
Tasks 4–7 are new files + `MainTabView` wiring — the highest surface area, do together.
Tasks 8–10 are polish + tests.
