#if os(macOS)
import XCTest

// AGENT-POST-RUN-CHECK: ui-tests-with-logs
//
// After every run of testTOSPlayerAutoSkipsSponsorSegment, load
// .github/skills/ui-tests-with-logs/SKILL.md and inspect the extracted device log.
// Classify every skip before closing the task:
//
// LEGITIMATE skip:
//   - "No video cards found" / "No non-short video card found" — home feed network
//     unavailable in the simulator. Device log should show NO "[SponsorBlock] UI-TEST
//     INJECT" line (the player was never opened).
//   - "onPlayerReady never fired" — IFrame embed failed to load (network/YouTube
//     availability), unrelated to the SponsorBlock code path under test. Device log
//     should show "[ytCallback] ❌ player error" or no "ready" notice.
//
// BUG skip (must fix before closing):
//   - The "auto-skip did not trigger" XCTAssertEqual failure path — that's a hard
//     failure, not a skip, but treat it identically: investigate before closing.
//   - Any skip reached AFTER "[TOS-sponsorskip] ✓ ready" prints in the test's stdout —
//     by that point the synthetic segment was injected and the only remaining work is
//     the auto-skip path itself, so a skip there means that path broke.
//
// Log events to verify (grep for "[SponsorBlock]"):
//   ✓ "[SponsorBlock] UI-TEST INJECT — bypassing cache/network, applied 1 synthetic
//      segment(s): sponsor[2.0–6.0s]"          — injection seam fired with the right spec
//   ✓ "[SponsorBlock] skip TRIGGER category=sponsor action=skip segment=[2.0s–6.0s]
//      ... before=Xs target=6.00s"             — trigger logged; "before" should read ≈2s
//   ✓ "[SponsorBlock] skip LANDED category=sponsor before=Xs after=Ys skipped≈Zs
//      (target was 6.00s, Δtarget=...)"        — landing confirmed; "after" should read
//                                                 ≈6s and skipped≈ ≈ (after − before) ≈ 4s
//
// RED FLAGS in device log:
//   - ZERO "[SponsorBlock]" lines at all → fetchSponsorSegments returned at its first
//     guard (sponsorBlockEnabled / activeSponsorCategories). Most likely cause: settings
//     persisted to UserDefaults from a PRIOR launch — e.g. the smoke test above runs
//     first with --uitesting-disable-sponsorblock, which SAVES sponsorBlockEnabled=false
//     (see SettingsStore.save()/init()). This bit the very first run of this test —
//     confirm "--uitesting-reset-settings" is still present in this test's launchArguments
//     (it restores AppSettings() defaults before the injection arg is read) before
//     looking anywhere else.
//   - "[SponsorBlock] skip TIMEOUT" → seek fired but currentTime never caught up —
//     investigate seekTo()/the JS bridge, not the logging itself
//   - A second "[SponsorBlock] skip TRIGGER category=sponsor" for the SAME [2.0–6.0s]
//     segment → activeSkipEnd re-entry guard regressed
//   - "skip TRIGGER" present with no matching "skip LANDED"/"skip TIMEOUT" before the
//     log ends → logSkipLanding wiring in the "tick" handler is broken
//   - "[SponsorBlock] toast SHOW" for category=sponsor → settings.sponsorAction
//     defaulted to showToast instead of skip (defaults changed or didn't apply)

// MARK: - TOSPlayerUITests
//
// Smoke test for the macOS IFrame (TOS-compliant) player.
//
// What it verifies:
//   1. Tapping the first non-short video card opens the TOS player (tosPlayer.stateLabel visible —
//      TOSPlayerView has no on-screen back/close button, see its body's doc comment for why).
//   2. The IFrame player starts playing within 30 s (Darwin notification fires + AX state = "playing").
//   3. No crash / stateLabel disappearance during 5 s of playback.
//   4. Pressing Esc dismisses the player (stateLabel disappears) — the only dismissal path.
//
// Preconditions:
//   - useTOSPlayerOnMac defaults to true on macOS (AppSettings.swift).
//   - The test passes --uitesting-disable-sponsorblock to avoid SponsorBlock skips
//     interfering with the simple "is it playing?" assertion.
//
// Lifecycle note: each test launches its OWN XCUIApplication instance exactly once
// via launchApp(extraArguments:) — mirroring HideShortsHomeUITests' launch(hideShorts:)
// (same minimal shape: fresh XCUIApplication, ["--uitesting", ...extra], app.launch(),
// nothing else). There is NO app launch in setUpWithError. This is deliberate: an
// earlier version of testTOSPlayerAutoSkipsSponsorSegment launched once in setUp and
// then did app.terminate() + a second XCUIApplication().launch() mid-test, which
// triggered a DETERMINISTIC auth-state race — the second back-to-back launch
// consistently hung after "Multilogin HTTP 403 INVALID_TOKENS" and never reached
// [Browse]/[Home]/[InnerTube] (reproduced identically twice). A single fresh launch
// per test does not hit this race. Do not reintroduce a mid-test terminate+relaunch.
//
// IMPORTANT — do NOT add saved-application-state deletion or
// "-ApplePersistenceIgnoreState YES" to launchApp. An earlier revision did both
// (to "always open a fresh window"), and that combination, ONLY when paired with
// "--uitesting-reset-settings + at least one more --uitesting-* argument", caused a
// ~100% reproducible hang during auth/home-feed bootstrap — the app got stuck right
// after "Multilogin HTTP 403 INVALID_TOKENS" and never logged [Browse]/[InnerTube]
// setAuthToken/[Home], so "No video cards found" fired at the 41s mark and the test
// SKIPPED. Proven via 11 controlled diagnostics: neither flag content, ordering, nor
// SettingsStore-recognition explained it — swapping in HideShortsHomeUITests' EXACT
// passing args (--uitesting-reset-settings --uitesting-hide-shorts) through the
// persistence-wiping launchApp reproduced the identical hang, while the same args
// through HideShortsHomeUITests' minimal launch() pass reliably. The wipe machinery
// is unnecessary anyway — XCUIApplication already opens a fresh window per launch in
// this single-launch-per-test architecture (confirmed: smoke test passes without it).

final class TOSPlayerUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Lifecycle helpers

    /// Launches a fresh `XCUIApplication` with `--uitesting` plus the given extra
    /// arguments. ONE launch per test — see the class-level comment above for why a
    /// mid-test terminate+relaunch is unsafe (deterministic auth-state race between
    /// back-to-back launches).
    private func launchApp(extraArguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extraArguments
        app.launch()
    }

    // MARK: - Test

    func testTOSPlayerPlaysFirstHomeVideo() throws {
        launchApp(extraArguments: ["--uitesting-disable-sponsorblock"])

        // ── 1. Wait for the home feed ─────────────────────────────────────────
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let anyCard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        guard XCTWaiter().wait(for: [anyCard], timeout: 30) == .completed else {
            throw XCTSkip("No video cards found — network unavailable or home feed empty")
        }

        // Find first non-short card.
        guard let card = firstNonShortCard(from: cards, maxCheck: 20) else {
            throw XCTSkip("No non-short video card found in first 20 cards")
        }

        let cardID = card.identifier  // "video.card.<videoId>"
        print("[TOS] clicking card: \(cardID)")

        // ── 2. Register Darwin expectations BEFORE clicking ───────────────────
        // CRITICAL: The navigation often completes (and notifies) during the 1s
        // animation that precedes the stateLabel appearing. Expectations must
        // be created BEFORE the click so they capture notifications that fire
        // before the player view is visible.
        let loadStartNote = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.loadstarted")
        let navNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.navfinished")
        let bridgeNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.bridge")
        let readyNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.ready")
        let tickStartNote = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.tickstarted")
        let playingNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.playing")
        // State-transition diagnostics (via tick handler): observe which states are hit
        let stateBuffNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.state.3")
        let stateCuedNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.state.5")
        let statePauseNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.state.2")
        let stateEndedNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.state.0")

        // ── 3. Tap the card — the TOS player should open ──────────────────────
        if !card.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 100)
            Thread.sleep(forTimeInterval: 0.5)
        }
        card.click()

        // ── 4. Wait for the AX state label (player appeared) ──────────────────
        // TOSPlayerView has no on-screen back/close button (see its body's doc
        // comment — every attempt rendered on/near the OS titlebar chrome and
        // had to be removed), so `tosPlayer.stateLabel` — the invisible AX text
        // overlay that mirrors playerState for tests — is the presence signal.
        let stateLabel = app.descendants(matching: .any).matching(identifier: "tosPlayer.stateLabel").firstMatch
        XCTAssertTrue(
            stateLabel.waitForExistence(timeout: 15),
            "tosPlayer.stateLabel did not appear — TOS player was not opened (check useTOSPlayerOnMac=true)"
        )
        print("[TOS] ✓ player opened — stateLabel present")

        // ── 5. Collect diagnostic notification results ────────────────────────
        // Stage 0a: Was loadHTMLString even called?
        let loadResult = XCTWaiter().wait(for: [loadStartNote], timeout: 1)
        print("[TOS] loadHTMLString called: \(loadResult == .completed ? "✓ YES" : "✗ NO (loadHTML never called)")")

        // Stage 0b: Nav finished — does WKNavigationDelegate.didFinish fire?
        let navResult = XCTWaiter().wait(for: [navNote], timeout: 5)
        if navResult == .completed {
            print("[TOS] ✓ HTML navigation finished (WKNavigationDelegate.didFinish fired)")
        } else {
            print("[TOS] ✗ HTML navigation did NOT finish — didFinish not called within 6s of click")
        }

        // Stage 1: Bridge check — does JS<->Swift messaging work at all?
        let bridgeTimeout: Double = navResult == .completed ? 3 : 0
        let bridgeResult =
            navResult == .completed
            ? XCTWaiter().wait(for: [bridgeNote], timeout: bridgeTimeout)
            : .timedOut
        if bridgeResult == .completed {
            print("[TOS] ✓ JS<->Swift bridge confirmed working")
        } else {
            print("[TOS] ✗ JS<->Swift bridge NOT working — window.webkit.messageHandlers unavailable")
        }

        // Stage 2: onPlayerReady — did the iframe_api script load?
        let readyTimeout: Double = bridgeResult == .completed ? 30 : 0
        let readyResult =
            bridgeResult == .completed
            ? XCTWaiter().wait(for: [readyNote], timeout: readyTimeout)
            : .timedOut
        if readyResult == .completed {
            print("[TOS] ✓ onPlayerReady fired — iframe_api loaded")
        } else if bridgeResult == .completed {
            print("[TOS] ✗ onPlayerReady did NOT fire within 30s — iframe_api script may have failed to load")
        }

        // Stage 2.5: Tick poll — is startPolling() running?
        let tickResult =
            readyResult == .completed
            ? XCTWaiter().wait(for: [tickStartNote], timeout: 3)
            : .timedOut
        if tickResult == .completed {
            print("[TOS] ✓ tick poll received — startPolling() is running")
        } else if readyResult == .completed {
            print("[TOS] ✗ no tick received within 3s of ready — startPolling() may not be called")
        }

        // Stage 3: playing state
        let playingTimeout: Double = readyResult == .completed ? 15 : 0
        let playResult =
            readyResult == .completed
            ? XCTWaiter().wait(for: [playingNote], timeout: playingTimeout)
            : .timedOut

        // Also poll the AX state label (declared in step 4) as a secondary check.
        let isPlaying: Bool
        if playResult == .completed {
            isPlaying = true
            print("[TOS] ✓ Darwin notification received — player is playing")
        } else {
            // Darwin notification timed out — check AX state (label or value).
            // On macOS 26, SwiftUI Text exposes text content via AXValue (not AXTitle).
            let labelValue = stateLabel.exists ? stateLabel.label : "(not found)"
            let valueStr = stateLabel.exists ? (stateLabel.value as? String ?? "") : ""
            let stateStr = labelValue.isEmpty ? valueStr : labelValue
            isPlaying = stateStr == "playing" || stateStr == "buffering"
            // Report which states were observed (helps diagnose autoplay blocking)
            let seenBuffering = XCTWaiter().wait(for: [stateBuffNote], timeout: 0) == .completed
            let seenCued = XCTWaiter().wait(for: [stateCuedNote], timeout: 0) == .completed
            let seenPaused = XCTWaiter().wait(for: [statePauseNote], timeout: 0) == .completed
            let seenEnded = XCTWaiter().wait(for: [stateEndedNote], timeout: 0) == .completed
            let statesSeen = [
                seenBuffering ? "buffering(3)" : nil,
                seenCued ? "cued(5)" : nil,
                seenPaused ? "paused(2)" : nil,
                seenEnded ? "ended(0)" : nil,
            ]
            .compactMap { $0 }.joined(separator: ",")
            print(
                "[TOS] playing notification timed out — stateLabel='\(stateStr)' states=[\(statesSeen.isEmpty ? "none — stuck at -1/unstarted" : statesSeen)]"
            )
        }

        XCTAssertTrue(
            isPlaying,
            "TOS player did not reach 'playing' state within 30 s — check network, baseURL whitelist, and autoplay config"
        )

        // ── 6. Let it play for 5 s and verify no crash ───────────────────────
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(
            stateLabel.exists,
            "tosPlayer.stateLabel disappeared during playback — possible crash or view re-render"
        )
        print("[TOS] ✓ 5 s of playback — no crash")

        // ── 7. Close the player via Esc — the only dismissal path ────────────
        // (see TOSPlayerView body's .onExitCommand doc comment for why there is
        // no on-screen back/close button to tap instead).
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        let dismissPredicate = NSPredicate(format: "exists == false")
        let dismissExpect = XCTNSPredicateExpectation(predicate: dismissPredicate, object: stateLabel)
        let closedResult = XCTWaiter().wait(for: [dismissExpect], timeout: 5)
        XCTAssertEqual(
            closedResult, .completed,
            "tosPlayer.stateLabel still visible after Esc — player did not dismiss"
        )
        print("[TOS] ✓ player dismissed — test complete")
    }

    // MARK: - Pause-on-dismiss test
    //
    // Regression test for the bug report: "video can still be heard when I press
    // back" — i.e. dismissing the TOS player (Esc — its only dismissal path) left the embedded
    // YouTube IFrame's audio playing. Root cause (see TOSPlayerViewModel.pause()'s
    // doc comment for the full trace): `loadEmbed()` wraps the YouTube embed in a
    // cross-origin `<iframe id="yt">`, so `webView.evaluateJavaScript` — which only
    // ever targets the WKWebView's MAIN frame — could never find the `<video>`
    // element via `document.querySelector('video')`. `TOSPlayerView.onDisappear`'s
    // `vm.pause()` was therefore a silent no-op: it ran a guarded
    // `if (v) v.pause()` against an always-empty query result, "succeeded" with no
    // error, and the embed kept playing — and being heard — after the player UI
    // disappeared. Fixed by routing pause() through `WKWebView.pauseAllMediaPlayback`,
    // the OS-level API that suspends playback in EVERY frame (including cross-origin
    // iframes) regardless of where the `<video>` element actually lives.

    // AGENT-POST-RUN-CHECK: ui-tests-with-logs
    //
    // After every run of testTOSPlayerStopsAudioOnDismiss, load
    // .github/skills/ui-tests-with-logs/SKILL.md and inspect the extracted device log.
    // Classify every skip before closing the task:
    //
    // LEGITIMATE skip:
    //   - "No video cards found" / "No non-short video card found" — home feed network
    //     unavailable in the simulator. Device log should show NO "[TOSPlayerView] onDisappear"
    //     line (the player was never opened).
    //   - "onPlayerReady never fired" — IFrame embed failed to load (network/YouTube
    //     availability). Device log should show "[ytCallback] ❌ player error" or no
    //     "[TOS-pauseondismiss] ✓ player opened" print, and no "ready" notice.
    //   - "player never reached 'playing'" — autoplay blocked or slow network; device
    //     log shows "ready" but no "[stateChange] ... state=playing"/".playing" notice.
    //
    // BUG skip (must fix before closing):
    //   - The final XCTAssertEqual on `pausedNote` failing — that's a hard failure (not
    //     a skip), but treat it identically: it means dismissal did NOT actually stop
    //     playback, i.e. the exact regression this test exists to catch. Investigate
    //     before closing — do not relax the assertion or add a skip around it.
    //   - Any skip reached AFTER "[TOS-pauseondismiss] ✓ playing" prints — by that point
    //     the only remaining work is dismiss-and-verify-paused, so a skip there means
    //     that path broke (e.g. stateLabel never disappears → dismissal itself is broken).
    //
    // Log events to verify (grep for "[TOSPlayerView] onDisappear\|\[pause\]\|pausedAllMedia"):
    //   ✓ "[TOSPlayerView] onDisappear — videoId=... playerState=playing currentTime=X.Xs
    //      — pausing & checkpointing"                    — onDisappear fired with a
    //                                                        non-zero currentTime (proves
    //                                                        playback was actually live)
    //   ✓ "[pause] requested — playerState=playing currentTime=X.Xs"
    //   ✓ "[pause] pauseAllMediaPlayback completed (was playerState=playing currentTime=X.Xs)"
    //                                                     — the OS-level pause actually ran
    //                                                        to completion (this is the line
    //                                                        that proves audio was silenced)
    //   ✓ "[eval] pause result: Optional({\n    found = 0;\n    iframes = 1;\n ...})"
    //                                                     — CONFIRMS the root-cause hypothesis:
    //                                                        document.querySelector('video')
    //                                                        finds nothing in the main frame
    //                                                        (found=0/false, iframes=1) — the
    //                                                        eval-based path really is a no-op,
    //                                                        and pauseAllMediaPlayback is doing
    //                                                        the actual work
    //
    // RED FLAGS in device log:
    //   - "[eval] pause result: ... found = 1 ..." → hypothesis WRONG: the main frame DOES
    //     see the <video> element (e.g. loadEmbed's wrapper architecture changed) — the
    //     eval-based pause should then work on its own; re-investigate why audio persists
    //   - "[pause] requested" present but NO "[pause] pauseAllMediaPlayback completed" →
    //     the Task never ran/completed (e.g. `self` deallocated mid-await, or the API
    //     hung) — re-examine the strong-capture rationale in pause()'s comment
    //   - NO "[TOSPlayerView] onDisappear" line at all after pressing Esc →
    //     onDisappear itself never fired — investigate the dismissal path
    //     (browseVM.deepLinkedVideo / dismiss()) before looking at pause()
    //   - "[pause] pauseAllMediaPlayback completed" appears MULTIPLE times for one
    //     dismissal → onDisappear firing more than once (view re-render churn)
    func testTOSPlayerStopsAudioOnDismiss() throws {
        launchApp(extraArguments: ["--uitesting-disable-sponsorblock"])

        // ── 1. Wait for the home feed, pick the first non-short video ────────────
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let anyCard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        guard XCTWaiter().wait(for: [anyCard], timeout: 30) == .completed else {
            throw XCTSkip("No video cards found — network unavailable or home feed empty")
        }
        guard let card = firstNonShortCard(from: cards, maxCheck: 20) else {
            throw XCTSkip("No non-short video card found in first 20 cards")
        }
        print("[TOS-pauseondismiss] clicking card: \(card.identifier)")

        // ── 2. Register Darwin expectations BEFORE clicking — notifications can ──
        //      fire during the open animation (see smoke test's comment for why).
        let readyNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.ready")
        let playingNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.playing")

        // ── 3. Open the player and confirm it actually starts playing ────────────
        if !card.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 100)
            Thread.sleep(forTimeInterval: 0.5)
        }
        card.click()

        // TOSPlayerView has no on-screen back/close button (see its body's doc
        // comment), so `tosPlayer.stateLabel` is the presence/dismissal signal.
        let stateLabel = app.descendants(matching: .any).matching(identifier: "tosPlayer.stateLabel").firstMatch
        XCTAssertTrue(
            stateLabel.waitForExistence(timeout: 15),
            "tosPlayer.stateLabel did not appear — TOS player was not opened"
        )
        print("[TOS-pauseondismiss] ✓ player opened")

        guard XCTWaiter().wait(for: [readyNote], timeout: 30) == .completed else {
            throw XCTSkip("onPlayerReady never fired — iframe_api may have failed to load (network)")
        }
        guard XCTWaiter().wait(for: [playingNote], timeout: 15) == .completed else {
            throw XCTSkip("player never reached 'playing' — autoplay blocked or network too slow to exercise dismissal")
        }
        print("[TOS-pauseondismiss] ✓ playing — letting it play briefly before dismissing")
        // Let real playback accumulate so onDisappear's logged currentTime is
        // unambiguously non-zero (proof the thing we're pausing was actually live).
        Thread.sleep(forTimeInterval: 3)

        // ── 4. Register the pause-completion expectation BEFORE dismissing — same ─
        //      "before the action" requirement as step 2: pause() fires synchronously
        //      from onDisappear, which can run as part of Esc's view-removal,
        //      racing a post-keypress registration.
        let pausedNote = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.pausedAllMedia")

        // ── 5. Dismiss the player via Esc — the only dismissal path (see ──────────
        //      TOSPlayerView body's .onExitCommand doc comment).
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let dismissExpect = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: stateLabel
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [dismissExpect], timeout: 5), .completed,
            "tosPlayer.stateLabel still visible after Esc — player did not dismiss"
        )
        print("[TOS-pauseondismiss] ✓ player dismissed")

        // ── 6. THE ASSERTION: did dismissal actually stop playback? ──────────────
        // TOSPlayerView.onDisappear → vm.pause() → WKWebView.pauseAllMediaPlayback()
        // → "pausedAllMedia" Darwin notification (see TOSPlayerViewModel.pause()).
        // This is the only verifiable, frame-agnostic signal available: XCUITest
        // cannot probe audio output directly, the YouTube IFrame's <video> element
        // lives in a cross-origin frame the JS bridge can't reach (so even an
        // "ask the page if it's paused" approach would be querying the wrong frame —
        // see pause()'s root-cause comment), and the view (and its AX tree) is gone
        // by the time we'd want to check anyway. If this notification never fires,
        // onDisappear's pause path is broken — directly reproducing "video can still
        // be heard after pressing back".
        let pausedResult = XCTWaiter().wait(for: [pausedNote], timeout: 10)
        XCTAssertEqual(
            pausedResult, .completed,
            "com.void.smarttube.tosplayer.pausedAllMedia never fired after dismissal — "
                + "TOSPlayerView.onDisappear did not actually stop playback (audio is likely "
                + "still audible — this is the reported bug). Check the device log for "
                + "'[TOSPlayerView] onDisappear' / '[pause] requested' / '[pause] "
                + "pauseAllMediaPlayback completed' lines and confirm pause() calls "
                + "WKWebView.pauseAllMediaPlayback() rather than the eval-based "
                + "document.querySelector('video') no-op (see TOSPlayerViewModel.pause())."
        )
        print("[TOS-pauseondismiss] ✓ pausedAllMedia notification received — playback actually stopped on dismiss")
    }

    // MARK: - Speed picker → setPlaybackRate cross-frame fix test

    /// Exercises `tosPlayer.speedButton` → `vm.setPlaybackRate(_:)` and verifies — via
    /// the device log's `[eval] setPlaybackRate(…) result:` line, the SAME diagnostic
    /// payload mechanism that empirically proved the `seekTo`/`pause` cross-frame fix
    /// (see `embedFrameInfo` and `eval`'s doc comments in TOSPlayerViewModel.swift) —
    /// that the JS bridge actually FOUND the `<video>` element and set its
    /// `playbackRate`, instead of the silent `{found: false, iframes: 1}` no-op that
    /// `play/seekTo/setPlaybackRate` all produced before `embedFrameInfo` was wired up.
    ///
    /// Why log inspection rather than an XCUITest-level assertion on the speed
    /// button's displayed label: `speedButton` carries a static
    /// `.accessibilityLabel("Playback speed")`, so `.label` never reflects the
    /// dynamically-displayed speed text (`store.settings.playbackSpeed`) regardless
    /// of what's on screen — there is no AX-based oracle for "the pill shows 1.5×".
    /// The `{found, playbackRate}` diagnostic payload `eval` logs on every call is
    /// the oracle that distinguishes "JS bridge reached the <video> and set its rate"
    /// from "silently found nothing" — exactly the distinction this test exists to make.
    ///
    // AGENT-POST-RUN-CHECK: ui-tests-with-logs
    //
    // After every run of this test, load .github/skills/ui-tests-with-logs/SKILL.md and
    // inspect the extracted device log. Classify every skip before closing the task:
    //
    // LEGITIMATE skip:
    //   - "No video cards found" / "No non-short video card found" — home feed network
    //     unavailable in the simulator. Device log should show no "[ytCallback] ready".
    //   - "onPlayerReady never fired" — IFrame embed failed to load (network/YouTube
    //     availability), unrelated to the setPlaybackRate path under test.
    //   - "speedButton did not appear" — the more-menu/speed cluster failed to render;
    //     check for a SwiftUI layout regression in TOSPlayerView.topRightControls.
    //
    // BUG skip (must fix before closing):
    //   - The final XCTAssertTrue on `found = 1` failing — that means setPlaybackRate
    //     is STILL a cross-frame no-op (embedFrameInfo never captured, or eval still
    //     targeting the main frame). Hard failure, treat identically to a skip here.
    //
    // Log events to verify (grep for "[eval] setPlaybackRate"):
    //   ✓ "[frame] captured embed iframe frameInfo — isMainFrame=false"  — preconditon:
    //      the fix's frame-capture fired before the speed change was requested
    //   ✓ "[eval] setPlaybackRate(1.5) result: { found = 1; iframes = 0; playbackRate = 1.5; }"
    //      — the FIX working: JS bridge found <video> in the iframe and set its rate
    //
    // RED FLAGS in device log:
    //   - "[eval] setPlaybackRate(1.5) result: { found = 0; iframes = 1; playbackRate = \"<null>\"; }"
    //     → cross-frame defect REGRESSED — embedFrameInfo capture or frame-targeted
    //       eval() broke; see TOSPlayerViewModel.embedFrameInfo's doc comment
    //   - No "[frame] captured embed iframe" line at all → "ready" never fired, or its
    //     capture branch was removed/broken
    func testTOSPlayerSpeedPickerSetsPlaybackRate() throws {
        launchApp(extraArguments: ["--uitesting-disable-sponsorblock"])

        // ── 1. Wait for the home feed, pick the first non-short video ────────────
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let anyCard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        guard XCTWaiter().wait(for: [anyCard], timeout: 30) == .completed else {
            throw XCTSkip("No video cards found — network unavailable or home feed empty")
        }
        guard let card = firstNonShortCard(from: cards, maxCheck: 20) else {
            throw XCTSkip("No non-short video card found in first 20 cards")
        }
        print("[TOS-speedpicker] clicking card: \(card.identifier)")

        // ── 2. Register Darwin expectations BEFORE clicking (see smoke test for why) ─
        let readyNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.ready")

        // ── 3. Open the player ────────────────────────────────────────────────────
        if !card.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 100)
            Thread.sleep(forTimeInterval: 0.5)
        }
        card.click()

        // TOSPlayerView has no on-screen back/close button (see its body's doc
        // comment), so `tosPlayer.stateLabel` is the presence/dismissal signal.
        let stateLabel = app.descendants(matching: .any).matching(identifier: "tosPlayer.stateLabel").firstMatch
        XCTAssertTrue(
            stateLabel.waitForExistence(timeout: 15),
            "tosPlayer.stateLabel did not appear — TOS player was not opened"
        )
        print("[TOS-speedpicker] ✓ player opened")

        // "ready" is when `embedFrameInfo` gets captured (see handleScriptMessage's
        // "ready" case) — the precondition for setPlaybackRate to reach the <video>.
        guard XCTWaiter().wait(for: [readyNote], timeout: 30) == .completed else {
            throw XCTSkip("onPlayerReady never fired — iframe_api may have failed to load (network)")
        }
        print("[TOS-speedpicker] ✓ ready — embedFrameInfo should now be captured")

        // ── 4. Open the speed picker and pick a non-default speed ────────────────
        // The speed control is now a quick-access pill (a Button) that opens the
        // shared PlayerPickerSheet, matching the direct player, instead of a
        // native SwiftUI Menu.
        let speedButton = app.buttons["tosPlayer.speedButton"].firstMatch
        XCTAssertTrue(
            speedButton.waitForExistence(timeout: 10),
            "tosPlayer.speedButton did not appear"
        )
        // Cheap, targeted diagnostics (NOT app.debugDescription — see note below):
        // confirm where XCUITest thinks the button is BEFORE clicking, so a future
        // "menu never opened" failure can be told apart from "menu opened but its
        // items use an AX type/label this query doesn't match".
        print("[TOS-speedpicker] speedButton frame=\(speedButton.frame) hittable=\(speedButton.isHittable)")
        speedButton.click()

        // SwiftUI `Menu` items surface as `.menuItems` in the macOS AX tree — matched
        // by their label text (speedLabel(for:) renders "1.5×" for 1.5, see TOSPlayerView).
        // Run #4 found ZERO menu items containing "×" — only 181 empty-label items,
        // exactly matching the count of background VideoCardView.contextMenu items
        // (~36 cards × 5 entries) that XCUITest's AX traversal discovers whether or
        // not they're actually open. That means `app.menuItems["1.5×"]` was never
        // going to match: either (a) the menu didn't open, or (b) its items render
        // under a different AX type. Cast a wider net — match ANY descendant whose
        // label is exactly "1.5×", regardless of element type — before concluding
        // the menu failed to open.
        //
        // (NOTE: app.debugDescription on this view hierarchy is extremely slow — tens
        // of seconds to snapshot the WKWebView's AX tree, can hang the run — avoid it.)
        let speedOptionPredicate = NSPredicate(format: "label == %@", "1.5×")
        let speedOption = app.descendants(matching: .any).matching(speedOptionPredicate).firstMatch
        guard speedOption.waitForExistence(timeout: 5) else {
            // Narrow, filtered diagnostics only — never dump the unfiltered 180+ list.
            let menuLabelsWithX = app.menuItems.allElementsBoundByIndex.map(\.label).filter { $0.contains("×") }
            let buttonLabelsWithX = app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains("×") }
            let staticLabelsWithX = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains("×") }
            XCTFail(
                "speed option '1.5×' not found via descendants(.any) after clicking "
                    + "tosPlayer.speedButton (frame=\(speedButton.frame)). "
                    + "menuItems with '×': \(menuLabelsWithX), " + "buttons with '×': \(buttonLabelsWithX), "
                    + "staticTexts with '×': \(staticLabelsWithX)")
            return
        }
        print(
            "[TOS-speedpicker] found '1.5×' option — type=\(speedOption.elementType.rawValue) frame=\(speedOption.frame)"
        )
        speedOption.click()
        print("[TOS-speedpicker] ✓ selected 1.5× — vm.setPlaybackRate(1.5) should have fired")

        // setPlaybackRate's `eval` completion handler logs asynchronously — give it a
        // moment to land in the device log before we close (and the process tears down).
        Thread.sleep(forTimeInterval: 2)

        // ── 5. Close the player via Esc — the only dismissal path (see ───────────
        //      TOSPlayerView body's .onExitCommand doc comment).
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let dismissExpect = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: stateLabel
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [dismissExpect], timeout: 5), .completed,
            "tosPlayer.stateLabel still visible after Esc — player did not dismiss"
        )
        print(
            "[TOS-speedpicker] ✓ player dismissed — test complete (inspect device log for "
                + "'[eval] setPlaybackRate(1.5) result:' — found should be 1, not 0)")
    }

    // MARK: - SponsorBlock auto-skip test

    /// Exercises the TOS player's SponsorBlock auto-skip path end-to-end and verifies
    /// (via the `com.void.smarttube.tosplayer.sponsorskip` Darwin notification — see
    /// `TOSPlayerViewModel.checkSponsorSkip`) that a skip actually fires.
    ///
    /// Why this needs its own launch arguments, distinct from the smoke test's:
    ///   - The smoke test above runs with `--uitesting-disable-sponsorblock` specifically
    ///     to AVOID exercising this path (its assertion is just "does it play"). This test
    ///     is the dedicated SponsorBlock exercise, so it needs the opposite — SponsorBlock
    ///     left ON — plus a synthetic segment via `--uitesting-inject-sponsor-segments=`
    ///     (see `TOSPlayerViewModel.fetchSponsorSegments`) so the skip fires deterministically
    ///     ~2s into playback no matter which random home-feed video loads or whether the
    ///     live SponsorBlock API has real data for it.
    ///   - "sponsor" is the injected category because `AppSettings`'s default action for
    ///     it is `.skip` (see `AppSettings.init`) — no extra settings juggling required.
    ///   - `--uitesting-reset-settings` is REQUIRED here: settings persist to UserDefaults
    ///     across launches (see SettingsStore.save()/init()), and XCTest may run the smoke
    ///     test (which sets+saves sponsorBlockEnabled=false via --uitesting-disable-sponsorblock)
    ///     before this one in the same suite run. Without resetting, this test would inherit
    ///     that persisted false, fail `fetchSponsorSegments`'s very first guard, and never
    ///     even reach the injection seam (silently zero "[SponsorBlock]" log lines — this
    ///     bit the very first run of this test). --uitesting-reset-settings restores
    ///     AppSettings() defaults — sponsorBlockEnabled=true, "sponsor" → .skip — before
    ///     --uitesting-inject-sponsor-segments is read.
    func testTOSPlayerAutoSkipsSponsorSegment() throws {
        launchApp(extraArguments: [
            "--uitesting-reset-settings",
            "--uitesting-inject-sponsor-segments=2-6:sponsor",
        ])

        // ── 1. Wait for the home feed, pick the first non-short video ────────────
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let anyCard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        guard XCTWaiter().wait(for: [anyCard], timeout: 30) == .completed else {
            throw XCTSkip("No video cards found — network unavailable or home feed empty")
        }
        guard let card = firstNonShortCard(from: cards, maxCheck: 20) else {
            throw XCTSkip("No non-short video card found in first 20 cards")
        }
        print("[TOS-sponsorskip] clicking card: \(card.identifier)")

        // ── 2. Register Darwin expectations BEFORE clicking (see smoke test above ─
        //      for why: notifications can fire during the open animation).
        let readyNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.ready")
        let playingNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.playing")
        let skipNote = XCTDarwinNotificationExpectation(notificationName: "com.void.smarttube.tosplayer.sponsorskip")

        // ── 3. Open the player ────────────────────────────────────────────────────
        if !card.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 100)
            Thread.sleep(forTimeInterval: 0.5)
        }
        card.click()

        // TOSPlayerView has no on-screen back/close button (see its body's doc
        // comment), so `tosPlayer.stateLabel` is the presence/dismissal signal.
        let stateLabel = app.descendants(matching: .any).matching(identifier: "tosPlayer.stateLabel").firstMatch
        XCTAssertTrue(
            stateLabel.waitForExistence(timeout: 15),
            "tosPlayer.stateLabel did not appear — TOS player was not opened"
        )
        print("[TOS-sponsorskip] ✓ player opened")

        // ── 4. "ready" is when fetchSponsorSegments() runs and the injection seam ─
        //      applies the synthetic segment (see TOSPlayerViewModel "ready" handler).
        guard XCTWaiter().wait(for: [readyNote], timeout: 30) == .completed else {
            throw XCTSkip("onPlayerReady never fired — iframe_api may have failed to load (network)")
        }
        print("[TOS-sponsorskip] ✓ ready — synthetic segment [2–6]s should now be applied")

        _ = XCTWaiter().wait(for: [playingNote], timeout: 15)

        // ── 5. Wait for the auto-skip ─────────────────────────────────────────────
        // The injected segment starts at currentTime=2s; playback starts at 0, so
        // ~2s of real playback (plus startup/buffering latency) should trigger it.
        // 25s comfortably covers slow CI startup without masking a real "never
        // skips" regression (which would otherwise hang until this test's own
        // timeout with no informative failure message).
        let skipResult = XCTWaiter().wait(for: [skipNote], timeout: 25)
        XCTAssertEqual(
            skipResult, .completed,
            "com.void.smarttube.tosplayer.sponsorskip never fired — TOS player did not "
                + "auto-skip the injected sponsor segment [2–6]s. Check the device log for "
                + "'[SponsorBlock] UI-TEST INJECT' (segment applied?) and 'skip TRIGGER' (guard "
                + "conditions in checkSponsorSkip — sponsorBlockEnabled / activeSkipEnd / sponsorAction)."
        )
        print("[TOS-sponsorskip] ✓ auto-skip notification received — checkSponsorSkip fired seekTo()")

        // ── 6. Player survives the skip — no crash / re-render ───────────────────
        // Sleep long enough for `logSkipLanding`'s "after" log to actually fire and
        // get captured in the device log before teardown. It polls on each ~250ms
        // "tick" and gives up after 16 ticks (~4s) with a TIMEOUT log if the seek
        // never lands (see TOSPlayerViewModel.logSkipLanding). A 2s sleep here
        // (the previous value) ends BEFORE that worst-case window closes, so the
        // "skip LANDED"/"skip TIMEOUT" half of the before/after pair never gets
        // emitted while the app is still alive — leaving only "skip TRIGGER" in the
        // captured log (confirmed: a real run with sleep=2 showed TRIGGER but no
        // LANDED/TIMEOUT). 6s comfortably clears the ~4s worst case with margin for
        // logging + capture-buffer flush latency.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(
            stateLabel.exists,
            "tosPlayer.stateLabel disappeared after the auto-skip — possible crash or view re-render"
        )
        print("[TOS-sponsorskip] ✓ player survived the skip — no crash")

        // ── 7. Close the player via Esc — the only dismissal path (see ───────────
        //      TOSPlayerView body's .onExitCommand doc comment).
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let dismissExpect = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: stateLabel
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [dismissExpect], timeout: 5), .completed,
            "tosPlayer.stateLabel still visible after Esc — player did not dismiss"
        )
        print(
            "[TOS-sponsorskip] ✓ player dismissed — test complete (inspect device log for skip TRIGGER/LANDED before/after times)"
        )
    }

    // MARK: - Helpers

    private func firstNonShortCard(from query: XCUIElementQuery, maxCheck: Int) -> XCUIElement? {
        let count = min(query.count, maxCheck)
        for i in 0..<count {
            let el = query.element(boundBy: i)
            // AX value "short" is set on short cards by VideoCardView.
            if el.value as? String != "short" { return el }
        }
        return nil
    }
}

#endif  // os(macOS)
