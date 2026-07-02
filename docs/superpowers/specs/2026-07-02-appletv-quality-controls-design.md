# Apple TV Playback Quality Controls — Design

**Date:** 2026-07-02
**Branch:** `AppleTV-Quality-Controlls`

## Problem

On Apple TV there is no way to change playback quality per video. The quality
picker overlay (`qualityPickerOverlay`) exists and is fully wired for tvOS focus
handling, but nothing on tvOS opens it: the quick-access pill row below the
progress bar is `#if !os(tvOS)` and the …-menu has no quality row.

Additionally:

- Picking a quality in the player currently **overwrites the global default**
  (`AppSettings.preferredQuality`, shown as "Max Resolution" in Settings). The
  desired behavior is a persistent default plus a temporary per-video override.
- The `Cancel` buttons in the picker sheet headers (quality, speed, sleep timer,
  captions, audio track) use the default tvOS button style and render as a
  bright white lozenge that clashes with the dark sheet.

## Decisions

| Question | Decision |
|---|---|
| Per-video vs. default semantics | Per-video pick is **temporary** (current video only); next video starts at the Settings default. Matches YouTube's own apps. |
| Scope of semantics change | **All platforms** (iOS, macOS, tvOS) — picker code stays shared, no platform forks. |
| tvOS entry point | **…-menu row** below Playback Speed (no dedicated player-cluster button). |
| Settings label | Rename "Max Resolution" → **"Default Quality"**. |

## Design

### 1. Default quality (Settings)

`AppSettings.preferredQuality` remains the single persisted default, applied
whenever a new video loads. Only the visible label in `SettingsView.swift`
changes ("Max Resolution" → "Default Quality"). No storage or migration change.

### 2. Per-video quality is temporary (all platforms)

In `PlayerView+PickerOverlays.swift` (`qualityPickerOverlay`), remove the
`store.settings.preferredQuality = …` writes and the accompanying
`vm.updateSettings(store.settings)` calls from both the "Auto" row and the
format rows. A pick then only calls `vm.selectFormat(…)`.

Reset-on-next-video already works: `PlaybackQualityManager.reset()` clears
`selectedFormat` / `pendingQualityLabel` on each new video load, and the loading
path applies `settings.preferredQuality`.

**Precedence audit (required):** several mid-playback recovery/fallback paths
read `settings.preferredQuality` directly and would snap playback back to the
default after an error recovery, discarding the user's per-video pick. Each of
these call sites must prefer the active per-video selection
(`selectedFormat` / user intent) when one exists, falling back to
`settings.preferredQuality` otherwise:

- `PlaybackViewModel+Fallback.swift` (~lines 188, 931, 1067, 1486, 1535)
- `PlaybackQualityManager.swift` (~line 387, `applyPreferredQuality`-style path)
- `PlaybackViewModel+Loading.swift` (~lines 771, 894) — these run at load time
  where no per-video pick exists yet; verify and leave as-is if so.

### 3. tvOS entry point: Quality row in the …-menu

- Add `.quality` to `PlayerView.MoreMenuRow` (`PlayerView+tvOS.swift`) and
  insert it into `moreMenuVisibleRows` directly after `.speed`. (Note: the
  overlay comment says D-pad navigation moved to native `.focused()` bindings;
  confirm whether `moreMenuVisibleRows` is still live and update whichever
  mechanism is actually in use.)
- New `moreMenuQualityRow` in `PlayerView+Overlays.swift`, `#if os(tvOS)`,
  mirroring `moreMenuSpeedRow`: label "Quality" with system image `film.stack`,
  trailing text showing the current quality
  (`vm.selectedFormat?.qualityLabel ?? "Auto"`), gray focused-background
  highlight, accessibility identifier `player.moreMenu.qualityRow`.
- Row is hidden while `vm.availableFormats.isEmpty` (audio-only / not yet
  loaded), matching the iOS quick-access pill.
- Tap: `showMoreMenu = false; showQualityPicker = true`. Existing wiring in
  `PlayerView+Lifecycle.swift` (focus transfer, `onExitCommand` dismiss) already
  handles the picker itself; `isAnyOverlayVisible` already includes
  `showQualityPicker`.

### 4. White Cancel button fix (picker sheet headers)

On tvOS, the header `Cancel` buttons in all five picker overlays
(`qualityPickerOverlay`, `speedPickerOverlay`, `sleepTimerPickerOverlay`,
`captionPickerOverlay`, `audioTrackPickerOverlay` in
`PlayerView+PickerOverlays.swift`) get `.buttonStyle(.plain)` with the same
focused-state treatment the …-menu rows use (gray background
`Color.gray.opacity(0.35)` when focused, rounded corners), so focus stays
visible without the white system platter. iOS/macOS appearance unchanged
(conditional on `#if os(tvOS)`).

### 5. In-passing fix: Stats for Nerds row focus bug

`moreMenuStatsForNerdsRow` (`PlayerView+Overlays.swift:693`) highlights when
`.cancel` is focused (copy-paste bug) and has no `.focused` binding of its own,
making it unreachable with the Siri Remote. Add a `.statsForNerds` case to
`MoreMenuRow` with a proper focus binding and background.

## Error handling

- Empty `availableFormats`: quality row not shown (tvOS) / pill disabled (iOS) —
  unchanged behavior.
- Quality-switch failures continue through the existing recovery paths; the only
  change is selection precedence (per-video pick before default).

## Testing

- **Unit tests:** picking a format via the picker path must not mutate
  `AppSettings.preferredQuality`; recovery-path precedence prefers the active
  per-video selection over the default.
- **UI tests:** extend existing more-menu tests with
  `player.moreMenu.qualityRow` (row present, opens picker, shows current label).
- **Manual (tvOS simulator/device):** menu row focus order, picker focus-in and
  Menu-button dismissal, Cancel button appearance in all five sheets, per-video
  pick reverting to default on next video.

## Out of scope

- Exposing the quality setting/picker on iOS beyond current behavior (iOS hides
  the Settings picker intentionally).
- Dedicated quality button in the tvOS player control cluster.
- TOS/IFrame player quality control (embed player does not expose quality).
