# Apple TV Playback Quality Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-video quality selection on Apple TV via a …-menu row, with the Settings value acting as a true default (per-video picks are temporary on all platforms), plus fixing the white Cancel buttons in picker sheets.

**Architecture:** `PlaybackQualityManager` gains a `perVideoQuality` intent field (survives CDN-failure reverts of `selectedFormat`, cleared on new-video `reset()`) and an `effectiveQuality` accessor (per-video pick ?? persisted default). The quality picker stops writing `AppSettings.preferredQuality`; mid-playback recovery paths read `effectiveQuality` instead of settings. tvOS gets a `Quality` more-menu row that opens the existing, already-focus-wired `qualityPickerOverlay`.

**Tech Stack:** Swift 6 / SwiftUI, SPM package `SmartTubeIOS` (UI) + `SmartTubeIOSCore`, Swift Testing (`@Test` / `#expect`), XCTest UI tests in `SmartTubeApp/UITests` (tvOS target `SmartTubeTVUITests`).

**Spec:** `docs/superpowers/specs/2026-07-02-appletv-quality-controls-design.md`

**Working directory:** repo root is `/Users/veit/Dev/SmartTubeIOS`. All `swift build` / `swift test` commands run from `/Users/veit/Dev/SmartTubeIOS/SmartTubeIOS` (the SPM package dir). `xcodebuild` commands run from the repo root.

**Verified facts for the implementer (don't re-derive):**
- `moreMenuVisibleRows` in `PlayerView+tvOS.swift` is dead code — nothing references it; more-menu D-pad navigation is native SwiftUI focus via `.focused($moreMenuFocusedRow, equals:)` bindings, initial focus set to `.speed` in `PlayerView+Lifecycle.swift:416`.
- `AppSettings.VideoQuality.maxHeight` returns `nil` for `.auto`.
- `selectFormat(nil)` already reloads unconstrained (quality `.auto`) — per-video "Auto" works without touching settings.
- `PlaybackQualityManager.reset()` runs on each new video load and clears `selectedFormat`; the load path then applies `settings.preferredQuality`.
- `reloadDASHItem` early-returns when `delegate?.playerInfo == nil`, so unit tests with a nil-`playerInfo` mock delegate are safe.
- `PlaybackViewModel+Loading.swift:771/894` are load-time reads of `settings.preferredQuality` — no per-video pick can exist yet at that point; they stay unchanged. Same for `PlaybackViewModel+Fallback.swift:188` (exhaustiveRetry completion, initial load) and `~1486/1535` (prefetch warm-up in `launchPhase2` — cache warming only, never swaps the playing item): all audited, all load-time, all unchanged.
- `QualityRecoveryPolicy.swift` in Core is unreferenced; ignore it.
- Existing UI test `TVMoreMenuNavigationUITests` asserts relative focus movement only; a new row below Speed does not break it.
- UI tests reference the settings row by identifier `settings.preferredQualityPicker`, not by label — the rename is safe.

---

### Task 1: Per-video quality intent in PlaybackQualityManager

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/Managers/PlaybackQualityManager.swift`
- Create: `SmartTubeIOS/Tests/SmartTubeIOSTests/PerVideoQualityOverrideTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SmartTubeIOS/Tests/SmartTubeIOSTests/PerVideoQualityOverrideTests.swift`:

```swift
import Foundation
import AVFoundation
import Testing
@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - PerVideoQualityOverrideTests
//
// The quality picker's per-video pick must be temporary: it overrides the
// persisted default (AppSettings.preferredQuality) for the current video only.
// PlaybackQualityManager records the pick in `perVideoQuality` (survives
// CDN-failure reverts of `selectedFormat`) and exposes `effectiveQuality`
// (per-video pick ?? persisted default) for recovery/stream-selection paths.

// MARK: - Mocks

private final class MockPlayer: PlayerItemSwappable {
    var rate: Float = 0
    func replaceCurrentItem(with item: AVPlayerItem?) {}
}

@MainActor
private final class MockQualityDelegate: QualityContext, QualityEventHandler {
    var playerInfo: PlayerInfo? = nil
    var settings = AppSettings()
    var currentVideo: Video? = nil
    var currentTime: TimeInterval = 0
    var toastMessage: String? = nil
    var isSwappingItem = false
    var isQualityChangePending = false
    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo: TimeInterval) {}
    func qualityItemDidFail(error: Error?, quality: AppSettings.VideoQuality, hasAppliedH264Cap: Bool) async {}
    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {}
}

// MARK: - Tests

@Suite("Per-video quality override")
struct PerVideoQualityOverrideTests {

    private func makeFormat(height: Int) -> VideoFormat {
        VideoFormat(
            label: "\(height)p",
            width: height * 16 / 9, height: height, fps: 30,
            mimeType: "video/mp4; codecs=\"avc1.640028\"",
            url: URL(string: "https://example.com/\(height)")
        )
    }

    @MainActor
    private func makeManager(default quality: AppSettings.VideoQuality)
        -> (PlaybackQualityManager, MockQualityDelegate) {
        let mgr = PlaybackQualityManager(player: MockPlayer())
        let delegate = MockQualityDelegate()
        delegate.settings.preferredQuality = quality
        mgr.delegate = delegate
        return (mgr, delegate)  // caller keeps delegate alive (mgr.delegate is weak)
    }

    @Test("Picking a format records perVideoQuality and leaves the default untouched")
    @MainActor
    func pickRecordsIntentWithoutTouchingDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 720))
        #expect(mgr.perVideoQuality == .q720)
        #expect(delegate.settings.preferredQuality == .q480)
        #expect(mgr.effectiveQuality == .q720)
    }

    @Test("Explicitly picking Auto overrides a non-auto default")
    @MainActor
    func explicitAutoOverridesDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(nil)
        _ = delegate  // keep weak delegate alive through the assertions
        #expect(mgr.perVideoQuality == .auto)
        #expect(mgr.effectiveQuality == .auto)
    }

    @Test("With no pick, effectiveQuality falls back to the persisted default")
    @MainActor
    func noPickFallsBackToDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        _ = delegate
        #expect(mgr.perVideoQuality == nil)
        #expect(mgr.effectiveQuality == .q480)
    }

    @Test("reset() clears the per-video pick — next video starts at the default")
    @MainActor
    func resetClearsPerVideoPick() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 1080))
        mgr.reset()
        _ = delegate
        #expect(mgr.perVideoQuality == nil)
        #expect(mgr.effectiveQuality == .q480)
    }

    @Test("setSelectedFormatForCurrentPreference prefers the per-video pick over the default")
    @MainActor
    func cdnRevertRestoresPerVideoPick() {
        let (mgr, delegate) = makeManager(default: .q1080)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.selectFormat(makeFormat(height: 720))
        mgr.selectedFormat = nil  // simulate CDN-failure revert
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }

    @Test("setSelectedFormatForCurrentPreference uses the default when no pick exists")
    @MainActor
    func cdnRevertUsesDefaultWithoutPick() {
        let (mgr, delegate) = makeManager(default: .q720)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift test --filter PerVideoQualityOverrideTests 2>&1 | tail -20`

Expected: compile error — `value of type 'PlaybackQualityManager' has no member 'perVideoQuality'` (and `effectiveQuality`).

(If `swift test` cannot build the UI module on this machine, fall back to `xcodebuild test -workspace /Users/veit/Dev/SmartTubeIOS/SmartTube.xcworkspace -scheme SmartTubeIOS -destination 'platform=macOS' -only-testing:SmartTubeIOSTests/PerVideoQualityOverrideTests` — same expectation.)

- [ ] **Step 3: Implement in PlaybackQualityManager.swift**

3a. Add the state + accessor after the `pendingQualityLabel` declaration (currently line ~83, right after the `var pendingQualityLabel: String = ""` line):

```swift
    /// The user's quality pick for the *current video*, set by `selectFormat`.
    /// `nil` = no pick this video (the persisted default applies); `.auto` = the
    /// user explicitly chose Auto for this video. Unlike `selectedFormat`, this
    /// survives CDN-failure reverts; cleared only by `reset()` on a new video.
    var perVideoQuality: AppSettings.VideoQuality? = nil

    /// The quality cap recovery and stream-selection paths must honour:
    /// the per-video pick when one exists, otherwise the persisted default.
    var effectiveQuality: AppSettings.VideoQuality {
        perVideoQuality ?? delegate?.settings.preferredQuality ?? .auto
    }
```

3b. In `reset()`, add `perVideoQuality = nil` directly after `pendingQualityLabel = ""`.

3c. In `selectFormat(_:)`, the `quality` derivation currently sits *after* the `guard let delegate` early-return. Move it up so `perVideoQuality` is always recorded. Replace the section from `selectedFormat = format` through `let savedTime = delegate.currentTime` with:

```swift
        selectedFormat = format
        pendingQualityLabel = format?.qualityLabel ?? ""
        let quality: AppSettings.VideoQuality
        if let fmt = format {
            if let q = AppSettings.VideoQuality.from(height: fmt.height) {
                quality = q
            } else {
                playerLog.error("selectFormat: non-standard height \(fmt.height)p — no matching VideoQuality; falling back to .auto")
                assertionFailure("selectFormat received format with non-standard height \(fmt.height) not in VideoQuality enum")
                quality = .auto
            }
        } else {
            quality = .auto
        }
        // Per-video intent: overrides the persisted default for this video only.
        perVideoQuality = quality
        delegate?.toastMessage = format.map { "\($0.height)p" } ?? "Auto"
        qualityTask?.cancel()
        qualityTask = nil
        guard let delegate else {
            playerLog.error("[quality] selectFormat: delegate is nil — quality reload skipped")
            return
        }
        let savedTime = delegate.currentTime
```

(The old `let quality: AppSettings.VideoQuality` block between `let savedTime` and `qualityTask = Task {` is removed — it moved up.)

3d. Replace the body of `setSelectedFormatForCurrentPreference()` (currently reads `delegate?.settings.preferredQuality`):

```swift
    func setSelectedFormatForCurrentPreference() {
        guard let maxH = effectiveQuality.maxHeight else {
            selectedFormat = nil
            return
        }
        selectedFormat = availableFormats.first { $0.height <= maxH }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift test --filter PerVideoQualityOverrideTests 2>&1 | tail -10`
Expected: 6 tests PASS.

- [ ] **Step 5: Run the full unit-test suite (regression check)**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/Managers/PlaybackQualityManager.swift SmartTubeIOS/Tests/SmartTubeIOSTests/PerVideoQualityOverrideTests.swift
git commit -m "Add per-video quality intent to PlaybackQualityManager

perVideoQuality records the user's pick for the current video (survives
CDN-failure reverts of selectedFormat, cleared on reset()); effectiveQuality
resolves pick-else-default for recovery paths.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Recovery paths honour the per-video pick

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Quality.swift` (add accessor)
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift:922,931,1067` (inside `attemptURL(_:for:info:label:)` — runs both at initial load and during mid-playback 403 recovery)

- [ ] **Step 1: Add the accessor to PlaybackViewModel+Quality.swift**

Inside `extension PlaybackViewModel`, after the `selectFormat` function:

```swift
    /// Quality cap for recovery/stream-selection paths: the per-video pick when
    /// one exists, otherwise the persisted default (`settings.preferredQuality`).
    var effectiveQuality: AppSettings.VideoQuality {
        qualityManager.effectiveQuality
    }
```

- [ ] **Step 2: Update the HLS variant selection in PlaybackViewModel+Fallback.swift (~line 931)**

Replace:

```swift
                let preferredMaxH = settings.preferredQuality == .auto ? nil : settings.preferredQuality.maxHeight
```

with:

```swift
                // Per-video pick (when set) takes precedence over the persisted default —
                // a mid-playback 403 recovery must not silently revert the user's choice.
                let preferredMaxH = effectiveQuality.maxHeight
```

(`maxHeight` is `nil` for `.auto`, so semantics are identical when no cap applies.)

Also update the log line at ~922 from `preferredQuality=\(settings.preferredQuality)` to `effectiveQuality=\(effectiveQuality)`.

- [ ] **Step 3: Update the ABR hints in PlaybackViewModel+Fallback.swift (~line 1067)**

Replace:

```swift
        if applyHLSHints {
            if settings.preferredQuality != .auto, let maxH = settings.preferredQuality.maxHeight {
```

with:

```swift
        if applyHLSHints {
            if let maxH = effectiveQuality.maxHeight {
```

(The `else` branch — clearing constraints for Auto — stays as is.)

- [ ] **Step 4: Build and run the test suite**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5`
Expected: build succeeds, all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Quality.swift SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift
git commit -m "Recovery paths honour per-video quality pick over the default

attemptURL's variant selection and ABR hints now read effectiveQuality so a
mid-playback 403 recovery keeps the user's per-video choice instead of
snapping back to the Settings default.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Quality picker stops writing the global default

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift:46-85` (`qualityPickerOverlay`)

- [ ] **Step 1: Remove the settings writes from the Auto row**

In `qualityPickerOverlay`, the Auto button action currently reads:

```swift
                            pickerLog.notice("[qualityPicker] selected Auto (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))")
                            vm.selectFormat(nil)
                            store.settings.preferredQuality = .auto
                            vm.updateSettings(store.settings)
                            showQualityPicker = false
                            qualityToastMessage = "Auto quality"
```

Replace with (per-video only — the persisted default is managed in Settings):

```swift
                            pickerLog.notice("[qualityPicker] selected Auto (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))")
                            vm.selectFormat(nil)
                            showQualityPicker = false
                            qualityToastMessage = "Auto quality"
```

- [ ] **Step 2: Remove the settings writes from the format rows**

The `ForEach(vm.availableFormats)` button action currently reads:

```swift
                                pickerLog.notice("[qualityPicker] selected \(fmt.qualityLabel) (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))")
                                vm.selectFormat(fmt)
                                if let q = AppSettings.VideoQuality.from(height: fmt.height) {
                                    store.settings.preferredQuality = q
                                } else {
                                    pickerLog.error("Quality picker: non-standard height \(fmt.height)p — falling back to .auto")
                                    assertionFailure("Quality picker tapped for format with non-standard height \(fmt.height)")
                                    store.settings.preferredQuality = .auto
                                }
                                vm.updateSettings(store.settings)
                                showQualityPicker = false
                                qualityToastMessage = "\(fmt.qualityLabel) · may take up to 30s"
```

Replace with (`selectFormat` itself still asserts on non-standard heights):

```swift
                                pickerLog.notice("[qualityPicker] selected \(fmt.qualityLabel) (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))")
                                vm.selectFormat(fmt)
                                showQualityPicker = false
                                qualityToastMessage = "\(fmt.qualityLabel) · may take up to 30s"
```

- [ ] **Step 3: Build and run tests**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift
git commit -m "Quality picker picks are per-video — stop overwriting the default

Picking a quality in the player no longer writes AppSettings.preferredQuality;
the Settings value is now a true default applied to each new video.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: tvOS more-menu Quality row (+ Stats for Nerds focus fix, dead-code removal)

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+tvOS.swift:40-66` (`MoreMenuRow`, delete `moreMenuVisibleRows`)
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+Overlays.swift` (`moreMenuItems`, new `moreMenuQualityRow`, fix `moreMenuStatsForNerdsRow`)
- Modify: `SmartTubeApp/UITests/TVMoreMenuNavigationUITests.swift` (new UI test)

- [ ] **Step 1: Update MoreMenuRow and remove dead code in PlayerView+tvOS.swift**

Replace the `MoreMenuRow` enum, its doc comment, and the entire `moreMenuVisibleRows` property (lines ~40-66) with:

```swift
    // MARK: - MoreMenuRow

    /// Identifies each focusable row in the more menu overlay.
    /// Navigation is native SwiftUI focus via the `.focused($moreMenuFocusedRow, equals:)`
    /// binding on each row; initial focus is set to `.speed` when the menu opens
    /// (PlayerView+Lifecycle). The case value drives the row's focus highlight.
    enum MoreMenuRow: Hashable {
        case speed, quality, like, dislike, sleepTimer, audioOnly, queueShuffle, captions,
             audioTrack, description, comments, statsForNerds, cancel
    }
```

(`moreMenuVisibleRows` was dead code — nothing referenced it.)

- [ ] **Step 2: Add the Quality row to moreMenuItems in PlayerView+Overlays.swift**

In `moreMenuItems`, the tvOS block currently reads:

```swift
            #if os(tvOS)
            moreMenuSpeedRow
            #endif
```

Change to:

```swift
            #if os(tvOS)
            moreMenuSpeedRow
            moreMenuQualityRow
            #endif
```

- [ ] **Step 3: Add the moreMenuQualityRow view**

In the "More menu rows" section of `PlayerView+Overlays.swift`, directly after `moreMenuSpeedRow`'s closing brace, add:

```swift
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
```

(The current-quality label logic matches the iOS quick-access pill: `vm.selectedFormat?.qualityLabel ?? (vm.pendingQualityLabel.isEmpty ? "Auto" : vm.pendingQualityLabel)`.)

- [ ] **Step 4: Fix the Stats for Nerds row focus bug**

In `moreMenuStatsForNerdsRow`, the tvOS block currently reads (copy-paste bug — highlights when *Cancel* is focused, row itself has no focus binding):

```swift
        #if os(tvOS)
        .background(moreMenuFocusedRow == .cancel ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        #endif
```

Replace with:

```swift
        #if os(tvOS)
        .background(moreMenuFocusedRow == .statsForNerds ? Color.gray.opacity(0.35) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focused($moreMenuFocusedRow, equals: .statsForNerds)
        #endif
```

- [ ] **Step 5: Build for tvOS**

Run: `cd /Users/veit/Dev/SmartTubeIOS && xcodebuild -workspace SmartTube.xcworkspace -scheme "Smart Tube" -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

Also: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift build 2>&1 | tail -3` (macOS/iOS paths still compile — the new row is tvOS-gated).

- [ ] **Step 6: Add a UI test for the new row**

In `SmartTubeApp/UITests/TVMoreMenuNavigationUITests.swift`, after `test_DownThreeTimes_AdvancesOneRowPerPress`, add:

```swift
    /// The Quality row must be present in the more menu, directly reachable
    /// with one DOWN press from Speed, and it must open the quality picker.
    func test_QualityRow_ExistsAndOpensPicker() throws {
        try waitForMoreMenu()

        let qualityRow = element("player.moreMenu.qualityRow")
        XCTAssertTrue(qualityRow.waitForExistence(timeout: 5),
                      "player.moreMenu.qualityRow must be in the more menu")

        // Speed is focused initially; one DOWN lands on Quality (the next row).
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(focusedIdentifier(), "player.moreMenu.qualityRow",
                       "One DOWN from Speed must focus the Quality row")

        remote.press(.select)
        let picker = element("player.qualityPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 10),
                      "Selecting the Quality row must open the quality picker")
    }
```

(`element(_:)`, `focusedIdentifier()`, `waitForMoreMenu()` are existing helpers in this file. Note: the row only renders when `vm.availableFormats` is non-empty; `waitForMoreMenu()` already plays a real video, so formats are loaded. If formats can lag, the 5 s `waitForExistence` covers it.)

- [ ] **Step 7: Run the tvOS UI test (requires tvOS simulator + network)**

Run: `cd /Users/veit/Dev/SmartTubeIOS && xcodebuild test -workspace SmartTube.xcworkspace -scheme "Smart Tube" -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SmartTubeTVUITests/TVMoreMenuNavigationUITests 2>&1 | tail -15`
Expected: tests pass (the suite self-skips with a capture if the network/video is unavailable — a skip is acceptable here, note it in the commit).

- [ ] **Step 8: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+tvOS.swift SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+Overlays.swift SmartTubeApp/UITests/TVMoreMenuNavigationUITests.swift
git commit -m "Add Quality row to tvOS player more menu

Opens the existing qualityPickerOverlay (already focus-wired for tvOS).
Also fixes the Stats for Nerds row highlighting when Cancel was focused and
removes the dead moreMenuVisibleRows property.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Fix white Cancel buttons in picker sheet headers (tvOS)

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift` (style struct + 5 Cancel buttons)

- [ ] **Step 1: Add the shared button style**

At the bottom of `PlayerView+PickerOverlays.swift` (after the closing brace of `extension PlayerView`), add:

```swift
#if os(tvOS)
// MARK: - PickerHeaderButtonStyle (tvOS)

/// Flat style for the Cancel button in picker sheet headers. The default tvOS
/// button style renders a bright white platter that clashes with the dark
/// sheet material; this shows a gray highlight when focused instead, matching
/// the more-menu row treatment.
struct PickerHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PickerHeaderButtonLabel(configuration: configuration)
    }

    private struct PickerHeaderButtonLabel: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isFocused ? Color.gray.opacity(0.35) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif
```

- [ ] **Step 2: Apply the style to all five Cancel buttons**

Each picker header has the same pattern. Change all five occurrences (quality, speed, sleep timer, captions, audio track):

```swift
                    Button("Cancel") { showQualityPicker = false }
                        .padding()
```

becomes:

```swift
                    Button("Cancel") { showQualityPicker = false }
                        #if os(tvOS)
                        .buttonStyle(PickerHeaderButtonStyle())
                        #endif
                        .padding()
```

(Same edit with `showSpeedPicker`, `showSleepTimerPicker`, `showCaptionPicker`, `showAudioTrackPicker` respectively. Postfix `#if` on modifier chains is valid Swift 6.)

- [ ] **Step 3: Build for tvOS and macOS**

Run: `cd /Users/veit/Dev/SmartTubeIOS && xcodebuild -workspace SmartTube.xcworkspace -scheme "Smart Tube" -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -3 && cd SmartTubeIOS && swift build 2>&1 | tail -3`
Expected: both succeed.

- [ ] **Step 4: Visual check on the tvOS simulator (manual)**

Boot the app in the tvOS simulator, play a video, open the more menu → Playback Speed. Verify the Cancel button is no longer a white lozenge, and shows a gray highlight when focused (D-pad up from the speed list).

- [ ] **Step 5: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift
git commit -m "Fix white Cancel buttons in tvOS picker sheet headers

Default tvOS button style rendered a bright white platter on the dark sheet.
PickerHeaderButtonStyle shows a gray focus highlight instead, matching the
more-menu rows. iOS/macOS unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Rename the Settings label to "Default Quality"

**Files:**
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Settings/SettingsView.swift:97`
- Modify: `SmartTubeIOS/Sources/SmartTubeIOS/Localizable.xcstrings` (key rename)

- [ ] **Step 1: Rename the picker label**

In `SettingsView.swift`:

```swift
            Picker("Max Resolution", selection: $store.settings.preferredQuality) {
```

becomes:

```swift
            Picker("Default Quality", selection: $store.settings.preferredQuality) {
```

(The accessibility identifier `settings.preferredQualityPicker` stays — UI tests reference the identifier, not the label.)

- [ ] **Step 2: Update the localization catalog**

In `Localizable.xcstrings`, find the `"Max Resolution"` key and rename it to `"Default Quality"`, updating any per-language values accordingly (if the entry has no translations, just rename the key; the catalog also regenerates on build).

- [ ] **Step 3: Build**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift build 2>&1 | tail -3`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/veit/Dev/SmartTubeIOS
git add SmartTubeIOS/Sources/SmartTubeIOS/Views/Settings/SettingsView.swift SmartTubeIOS/Sources/SmartTubeIOS/Localizable.xcstrings
git commit -m "Rename Settings quality label to Default Quality

Per-video picks are temporary now, so the Settings value is a true default
rather than a sticky max resolution.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Final verification

- [ ] **Step 1: Full unit-test suite**

Run: `cd /Users/veit/Dev/SmartTubeIOS/SmartTubeIOS && swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 2: tvOS build**

Run: `cd /Users/veit/Dev/SmartTubeIOS && xcodebuild -workspace SmartTube.xcworkspace -scheme "Smart Tube" -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual end-to-end on the tvOS simulator**

1. Settings → Player → "Default Quality" set to 480p.
2. Play a video → … menu → Quality row shows a quality at or below 480p → pick 1080p → video reloads at 1080p.
3. Settings → "Default Quality" still shows 480p (not overwritten).
4. Play the *next* video → starts at ≤480p again (per-video pick did not stick).
5. In any picker sheet: Cancel is not a white lozenge; gray highlight when focused.
6. More menu: Stats for Nerds row highlights when focused (not when Cancel is).

- [ ] **Step 4: Use superpowers:verification-before-completion, then superpowers:finishing-a-development-branch**
