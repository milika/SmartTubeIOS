# Casio complication for Apple Watch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rectangular Casio F-91W complication for Apple Watch faces, carried by a minimal watch app embedded in the iPhone app.

**Architecture:** Spec `docs/superpowers/specs/2026-10-09-casio-watch-complication-design.md`. The package gains watchOS 10 support, a `CasioComplicationModel` protocol, a generic watchOS-only complication widget and the F-91W layout. Two new Xcode targets (watch app, complication extension) are added with the `xcodeproj` gem; the iPhone app embeds the watch app (iOS only).

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit (accessoryRectangular), watchOS 10 / iOS 17, Xcode 27, xcodeproj gem 1.27.

Package paths are relative to `Widgets/CasioClockWidget/`, `SRC = Sources/CasioClockWidget`.
Package tests: `swift test --scratch-path ~/DevTemp/smarttube/derived-data/casio`.
Package watchOS build: `xcodebuild -scheme CasioClockWidget -destination 'generic/platform=watchOS' -derivedDataPath ~/DevTemp/smarttube/derived-data/casio-watch build` (run in the package folder).

---

### Task 1: Package builds for watchOS

- [ ] `Package.swift`: `platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)]`.
- [ ] Wrap the whole contents (after the imports) of `SRC/Widget/CasioWatchWidget.swift` and `SRC/Models/F91W/CasioF91WWidget.swift` in `#if !os(watchOS)` … `#endif`, with a one-line reason: `// The iPhone widget (systemSmall doesn't exist on watchOS).`
- [ ] Run the watchOS build: expect `BUILD SUCCEEDED` (if anything else fails on watchOS, guard it the same way and note it here). Run tests: pass. Commit `feat: Casio widget package builds for watchOS`.

### Task 2: Complication model and widget

- [ ] Failing test, add to `Tests/CasioClockWidgetTests/ModelTests.swift`:

```swift
    @Test("complication kinds are unique and differ from the iPhone kinds")
    func complicationKinds() {
        let kinds = CasioModels.all.map { $0.kind } + CasioModels.complications.map { $0.complicationKind }
        #expect(Set(kinds).count == kinds.count)
        #expect(CasioF91W.complicationKind == "CasioF91WComplication")
    }
```

Run: fails to compile (`complications`, `complicationKind`).
- [ ] `SRC/CasioModel.swift`, add:

```swift
/// A model that also has a rectangular Apple Watch complication.
protocol CasioComplicationModel: CasioModel {
    associatedtype RectangularComplication: View
    /// Stable WidgetKit kind of the complication (different from `kind`).
    static var complicationKind: String { get }
    /// Name and description in the complication picker.
    static var complicationName: String { get }
    static var complicationSummary: String { get }
    @ViewBuilder static func rectangularComplication(_ context: CasioFaceContext) -> RectangularComplication
}
```

and in `CasioModels`: `static let complications: [any CasioComplicationModel.Type] = [CasioF91W.self]`.
- [ ] `SRC/Models/F91W/F91WComplication.swift` (the layout; numbers tuned in Task 3):

```swift
import SwiftUI
import WidgetKit

/// The F-91W's LCD as a rectangular complication, on a 200×80 canvas: PM / weekday / date on
/// top, H:MM and live seconds below. Full-colour faces get the grey-green glass and dark ink;
/// tinted faces get white ink in the face's tint (no glass).
struct F91WComplication: View {
    static let canvas = CGSize(width: 200, height: 80)

    let context: CasioFaceContext
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fullColor: Bool { renderingMode == .fullColor }

    private var style: LCDStyle {
        var s = CasioF91W.lcd
        if !fullColor {
            s.ink = .white
            s.unlitOpacity = 0.12
        }
        return s
    }

    var body: some View {
        let parts = DisplayParts.make(
            for: context.date, calendar: context.calendar, twelveHour: context.uses12HourClock,
            blankDigit: style.digits.blankDigit)
        FaceCanvas(size: Self.canvas) {
            if fullColor {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.glass)
                    .frame(width: Self.canvas.width, height: Self.canvas.height)
            }
            Group {
                if let marker = parts.marker {
                    Text(marker)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(style.ink)
                        .place(leading: 8, centerY: 14, width: 40)
                }
                LCDText(
                    text: parts.weekday, font: style.letters, glyph: 17, edge: .leading(62), baseline: 22,
                    tracking: 3, style: style)
                LCDText(
                    text: parts.day, font: style.digits, glyph: 19, edge: .trailing(194), baseline: 23, width: 60,
                    tracking: 2, style: style)
                LCDText(
                    text: parts.hoursMinutes, font: style.digits, glyph: 44, edge: .trailing(148), baseline: 75,
                    width: 160, xScale: CasioF91W.digitSqueeze, style: style)
                LiveSeconds(
                    date: context.date, calendar: context.calendar, previewSeconds: context.previewSeconds,
                    glyph: 32, trailing: 196, baseline: 75, xScale: CasioF91W.digitSqueeze, style: style)
            }
            .widgetAccentable()
        }
    }
}
```

- [ ] `SRC/Models/F91W/CasioF91W.swift`: `enum CasioF91W: CasioComplicationModel` and

```swift
    static let complicationKind = "CasioF91WComplication"
    static let complicationName = "Casio F-91W"
    static let complicationSummary = "The F-91W's display: time with live seconds, day and date."

    static func rectangularComplication(_ context: CasioFaceContext) -> some View {
        F91WComplication(context: context)
    }
```

- [ ] `SRC/Widget/CasioComplicationWidget.swift`:

```swift
#if os(watchOS)
import SwiftUI
import WidgetKit

/// A model's rectangular Apple Watch complication (Modular faces, Smart Stack). Watch
/// complications can't run a tap action, so there is no light; a tap opens the watch app.
/// Internal: each model exposes a public wrapper (see CasioF91WComplication).
struct CasioComplicationWidget<Model: CasioComplicationModel>: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Model.complicationKind, provider: CasioClockProvider(model: Model.complicationKind)) {
            entry in
            Model.rectangularComplication(CasioFaceContext(date: entry.date))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Model.complicationName)
        .description(Model.complicationSummary)
        .supportedFamilies([.accessoryRectangular])
    }
}
#endif
```

- [ ] `SRC/Models/F91W/CasioF91WComplication.swift`:

```swift
#if os(watchOS)
import SwiftUI
import WidgetKit

/// Casio F-91W rectangular complication: list `CasioF91WComplication()` in a watchOS WidgetBundle.
public struct CasioF91WComplication: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioComplicationWidget<CasioF91W>().body }
}

#Preview("F-91W", as: .accessoryRectangular) {
    CasioF91WComplication()
} timeline: {
    CasioClockEntry(date: .now)
}
#endif
```

- [ ] Public preview view for the watch app's screen, `SRC/Models/F91W/CasioF91WComplication.swift` (outside the `#if`, all platforms):

```swift
/// The F-91W complication as a plain view (the watch app shows it as a preview).
public struct CasioF91WComplicationPreview: View {
    public init() {}
    public var body: some View {
        TimelineView(.everyMinute) { tl in
            CasioF91W.rectangularComplication(CasioFaceContext(date: tl.date))
        }
    }
}
```

(with `import SwiftUI` at the top of the file, outside the `#if`).
- [ ] Tests pass; watchOS build succeeds. Commit `feat: Casio F-91W rectangular complication (package)`.

### Task 3: Tune the layout (macOS render)

- [ ] Temporary render test (not committed) drawing `F91WComplication` at 4× in both modes: full colour, and accented simulated with `.environment(\.widgetRenderingMode, .accented)` on a black background. Save to `~/DevTemp/smarttube/scratch/measure/complication-*.png`.
- [ ] Check: nothing clipped at "12:59 59", "23:59" (24 h), "WE 30"; rows don't overlap; seconds baseline = H:MM baseline. Adjust numbers in `F91WComplication`, re-render, commit `fix: tune the Casio complication layout` if changed.

### Task 4: Xcode targets

- [ ] Sources:
  - `SmartTubeApp/Watch/SmartTubeWatchApp.swift`:

```swift
import CasioClockWidget
import SwiftUI

/// The minimal watch app that carries the Casio complication: a live preview and how to add it.
@main
struct SmartTubeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    CasioF91WComplicationPreview()
                        .frame(height: 64)
                        .environment(\.colorScheme, .dark)
                    Text("Casio F-91W complication")
                        .font(.headline)
                    Text(
                        "Touch and hold the watch face, tap Edit, swipe to Complications, choose a large slot and pick SmartTube."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
```

  - `SmartTubeApp/Watch/Assets.xcassets/AppIcon.appiconset/` with `Contents.json` (single universal watchOS 1024 image) and `AppIcon.png` = the iPhone 1024 icon.
  - `SmartTubeApp/WatchComplications/CasioComplications.swift`:

```swift
import CasioClockWidget
import SwiftUI
import WidgetKit

@main
struct CasioComplications: WidgetBundle {
    var body: some Widget {
        CasioF91WComplication()
    }
}
```

  - `SmartTubeApp/WatchComplications/Info.plist`: as `DownloadWidget/Info.plist` with `CFBundleDisplayName` "Casio".
- [ ] Script `~/DevTemp/smarttube/scratch/watch/add_watch_targets.rb` (xcodeproj gem; not committed): creates the two targets with the settings in the spec (SDKROOT watchos, SUPPORTED_PLATFORMS "watchos watchsimulator", TARGETED_DEVICE_FAMILY 4, WATCHOS_DEPLOYMENT_TARGET 10.0, team 5A4JA438MW, automatic signing, MARKETING_VERSION / CURRENT_PROJECT_VERSION from the app target, SWIFT_VERSION 5.9, SKIP_INSTALL YES, generated Info.plist keys for the app, INFOPLIST_FILE for the extension, APPLICATION_EXTENSION_API_ONLY YES), source/resource phases, the `CasioClockWidget` package product on both, "Embed Foundation Extensions" in the watch app, "Embed Watch Content" (dstSubfolderSpec 16, `$(CONTENTS_FOLDER_PATH)/Watch`) and dependency in `SmartTube` with `platform_filter = 'ios'`.
- [ ] `xcodebuild -list` shows the targets; iOS build (AGENTS command) succeeds; `ls …/SmartTube.app/Watch/SmartTube.app/PlugIns/` lists `SmartTubeWatchComplications.appex`. `git checkout -- SmartTubeApp/SmartTubeApp/Info-macOS.plist`.
- [ ] Commit `feat: watch app carrying the Casio complication` (sources + project).

### Task 5: Simulator check

- [ ] After the runtime download: `xcrun simctl create "SmartTube Watch" <Apple Watch device type> <watchOS 27 runtime>`, `xcrun simctl pair <watch> BE5124D6-…`, boot.
- [ ] Install `…/SmartTube.app/Watch/SmartTube.app` on the watch simulator, launch, screenshot (live preview).
- [ ] Try the face editor (Modular face → large slot → SmartTube) with the simulator tool; screenshot if it works.

### Task 6: Docs and task

- [ ] Package README: watchOS section (complication, `CasioF91WComplication()`, add-a-model step for complications). Commit.
- [ ] Private task #356: watch part, what was checked.
