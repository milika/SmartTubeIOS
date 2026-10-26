---
paths: ["**/*.swift"]
---

<!-- synced with AGENTS.md rev 1 -->

- Swift 6 strict concurrency everywhere. View models are `@MainActor @Observable`. No `ObservableObject`, `@Published`, Combine, `DispatchQueue`, completion handlers in new code.
- `SmartTubeIOSCore` must stay Foundation-only (no SwiftUI/UIKit/AVFoundation/WebKit). Put platform code in `SmartTubeIOS`.
- One definition per constant/identifier/threshold. Accessibility identifiers come from `AccessibilityID`; SF Symbols from `AppSymbol`; playback timeouts from `PlaybackTuning`.
- Signing and bundle identity live in `SmartTubeApp/Config/Base.xcconfig` (`SMARTTUBE_TEAM_ID`, `SMARTTUBE_BUNDLE_PREFIX`); machine-local overrides go in the gitignored `Config/Secrets.xcconfig`. Never hardcode a team, bundle ID, version or App Group — read the group through `AppGroup.identifier`. `just identity` prints the effective values, `just identity-check` (in `just ci`) fails if they reappear in `project.pbxproj`.
- Wrap UIKit-only API in `#if os(iOS)`; provide AppKit/tvOS branches. Never nest `NavigationStack`s.
- Never hand-edit `project.pbxproj` (a hook blocks it).
- Tests: Swift Testing for unit tests; no `Task.sleep`, no live network, fakes at protocol seams. UI tests use `AccessibilityID` and `waitForExistence`, never `sleep`.
- Logging via `os.Logger` (subsystem `AppSubsystem`), never `print`.
