# Casio widget: several watch models — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the single-file Casio F-91W widget package into a shared kit plus one folder per watch model, so new Casio models are easy to add; the F-91W must look pixel-identical.

**Architecture:** Spec: `docs/superpowers/specs/2026-10-09-casio-widget-models-design.md`. Kit (canvas placement, fonts, shapes, text effects), LCD (DSEG fonts, style, LCD text, live seconds, glass, formatting), Widget (internal generic widget + provider + per-model backlight intent), Models/F91W. Models are internal; each gets a small public `Widget` wrapper.

**Tech Stack:** Swift 5.9 package, SwiftUI, WidgetKit, AppIntents, swift-testing. iOS 17 / macOS 14.

All paths below are relative to `Widgets/CasioClockWidget/` unless they start with `SmartTubeApp/`.
`SRC = Sources/CasioClockWidget`, current single file: `SRC/CasioClockWidget.swift` (line numbers refer to it at commit `2664a276`).
Test command (run from the package folder): `swift test --scratch-path ~/DevTemp/smarttube/derived-data/casio`

---

### Task 0: Reference renders (not committed)

- [ ] Copy the current renders: `mkdir -p ~/DevTemp/smarttube/scratch/measure/before && cp ~/DevTemp/smarttube/scratch/measure/render*.png ~/DevTemp/smarttube/scratch/measure/before/`
- [ ] Pixel-compare helper `~/DevTemp/smarttube/scratch/measure/samepixels.py`:

```python
import sys
from PIL import Image, ImageChops
a = Image.open(sys.argv[1]).convert("RGBA"); b = Image.open(sys.argv[2]).convert("RGBA")
print("size", a.size, b.size)
box = ImageChops.difference(a, b).getbbox()
print("IDENTICAL" if box is None else f"DIFFERENT in {box}")
```

The temporary render test (`Tests/CasioClockWidgetTests/RenderPreviewTests.swift`, never committed) is rewritten in Task 3 for the new API.

### Task 1: Kit (pure moves)

**Files:** Create `SRC/Kit/BundledFonts.swift`, `SRC/Kit/CaseFont.swift`, `SRC/Kit/Shapes.swift`, `SRC/Kit/TextEffects.swift`, `SRC/Kit/FaceCanvas.swift`. Modify `SRC/CasioClockWidget.swift`.

- [ ] `Kit/BundledFonts.swift`: registration taken out of `LCDFont` (lines 135-142):

```swift
import CoreText
import Foundation

/// Registers every font in the package's resources once, for all models.
enum BundledFonts {
    static func register() { _ = registered }

    private static let registered: Bool = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()
}
```

- [ ] `Kit/CaseFont.swift`:

```swift
import SwiftUI

/// Fonts for text printed on a watch case, by PostScript name (bundled in Resources/).
enum CaseFont {
    static func custom(_ postScriptName: String, _ size: CGFloat) -> Font {
        BundledFonts.register()
        return .custom(postScriptName, fixedSize: size)
    }
}
```

- [ ] `Kit/Shapes.swift`: move `CutCornerRect` (lines 504-530) and `Pointer` (532-550) verbatim; `Pointer` becomes `struct Pointer` (internal, not private). Doc comment of `CutCornerRect` stays.
- [ ] `Kit/TextEffects.swift`: move `emboldened` and `oblique` (lines 555-571) into `extension View { … }` with `fileprivate` → internal (drop the keyword).
- [ ] `Kit/FaceCanvas.swift`: move the five `place(...)` modifiers (lines 573-616) into `extension View`, `fileprivate` → internal, and add the canvas container (from `CasioWatchFace.body`, lines 222-234):

```swift
import SwiftUI

/// Draws `content` on a fixed canvas (points measured from a photo of the watch) and scales it
/// to fit the space it is given.
struct FaceCanvas<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack(alignment: .topLeading) { content() }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
```

- [ ] In `SRC/CasioClockWidget.swift`: delete the moved code; `LCDFont.font(height:)` calls `BundledFonts.register()`; `CaseFont` there is deleted and its four helpers become `private` statics on `CasioWatchFace` for now (`CaseFont.custom("Michroma-Regular", size)` etc.); `CasioWatchFace.body` uses `FaceCanvas(size: Self.canvas) { bezel; printedFace; lcd }`.
- [ ] Run tests: all pass (7 + any). Commit `refactor: Casio widget kit (fonts, shapes, text effects, canvas)`.

### Task 2: LCD parts

**Files:** Create `SRC/LCD/LCDFont.swift`, `LCDStyle.swift`, `DisplayParts.swift`, `LCDText.swift`, `LiveSeconds.swift`, `LCDWindow.swift`. Modify `SRC/CasioClockWidget.swift`, tests.

- [ ] `LCD/LCDFont.swift`: move `LCDFont` (lines 106-156) without the registration (uses `BundledFonts.register()`).
- [ ] `LCD/LCDStyle.swift` (replaces `CasioFaceStyle`, adds the model's backlight):

```swift
import SwiftUI

/// How a model's LCD looks: segment fonts, glass, ink, faint unlit segments and backlight.
struct LCDStyle {
    var digits: LCDFont = .dseg7("BoldItalic")
    var letters: LCDFont = .dseg14("BoldItalic")
    /// Opacity of the unlit segments behind the characters; 0 = off.
    var unlitOpacity: Double = 0.055
    var glass: Color = Color(red: 0.67, green: 0.74, blue: 0.68)
    var ink: Color = Color(red: 0.11, green: 0.16, blue: 0.19)
    var backlight: Color = Color(red: 0.36, green: 0.86, blue: 0.62)
    /// Backlight opacity from the leading to the trailing edge (one LED at the left: fades right).
    var backlightFalloff: [Double] = [1, 0.75, 0.45]
}
```

- [ ] `LCD/DisplayParts.swift`: the `DisplayParts` struct (lines 470-479) becomes top-level; `weekdays`, `figureSpace`, `displayParts(...)` (lines 481-501) become `static let`/`static func make(for:calendar:twelveHour:blankDigit:)` on it, and `localeUses12HourClock` (lines 218-220) moves here too.
- [ ] Tests: `CasioWatchFace.displayParts(` → `DisplayParts.make(`, `CasioWatchFace.figureSpace` → `DisplayParts.figureSpace`.
- [ ] `LCD/LCDText.swift` (from `lcdText`, lines 416-437):

```swift
import SwiftUI

/// LCD characters with their unlit segments faintly behind them, placed by baseline.
struct LCDText: View {
    enum Edge { case leading(CGFloat), trailing(CGFloat) }

    let text: String
    let font: LCDFont
    let glyph: CGFloat
    let edge: Edge
    let baseline: CGFloat
    var width: CGFloat = 200
    var tracking: CGFloat = 0
    /// Horizontal squeeze (1 = DSEG's own width).
    var xScale: CGFloat = 1
    let style: LCDStyle

    var body: some View {
        let layers: [(String, Double)] =
            [(font.allLit(text), style.unlitOpacity), (text, 1)].compactMap { item in
                guard let t = item.0, item.1 > 0 else { return nil }
                return (t, item.1)
            }
        ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
            let view = Text(layer.0).font(font.font(height: glyph)).tracking(tracking)
                .foregroundStyle(style.ink.opacity(layer.1))
            switch edge {
            case .leading(let x):
                view.scaleEffect(x: xScale, y: 1, anchor: .leading)
                    .place(leading: x, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            case .trailing(let x):
                view.scaleEffect(x: xScale, y: 1, anchor: .trailing)
                    .place(trailing: x, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            }
        }
    }
}
```

- [ ] `LCD/LiveSeconds.swift` (from `seconds`, lines 439-466), parameters instead of F-91W constants:

```swift
import SwiftUI

/// Live seconds: timer text counting up from the start of the minute ("0:23"), shown through a
/// right-aligned window that keeps only the last two digits.
struct LiveSeconds: View {
    let date: Date
    let calendar: Calendar
    /// Fixed seconds for static renders (the timer only animates inside a widget).
    let previewSeconds: Int?
    let glyph: CGFloat
    let trailing: CGFloat
    let baseline: CGFloat
    var xScale: CGFloat = 1
    let style: LCDStyle

    var body: some View {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let font = style.digits
        let digitAdvance = glyph / font.glyphToEm * font.digitAdvance
        let window = digitAdvance * 2.02
        let live: Text = previewSeconds.map { Text(String(format: "%02d", $0)) } ?? Text(minuteStart, style: .timer)
        ZStack(alignment: .topLeading) {
            if style.unlitOpacity > 0, let lit = font.allLit("00") {
                Text(lit).font(font.font(height: glyph))
                    .foregroundStyle(style.ink.opacity(style.unlitOpacity))
                    .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                    .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
            }
            live
                .font(font.font(height: glyph))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: digitAdvance * 6, alignment: .trailing)
                .frame(width: window, alignment: .trailing)
                .clipped()
                .scaleEffect(x: xScale, y: 1, anchor: .trailing)
                .place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: window)
        }
    }
}
```

- [ ] `LCD/LCDWindow.swift` (from the frame + glass part of `lcd`, lines 365-393):

```swift
import SwiftUI

/// The LCD's framed dark surround and its glass, lit by the backlight when `backlit`.
struct LCDWindow: View {
    /// Outer rectangle of the dark surround and its outline.
    let frame: CGRect
    var frameRadius: CGFloat = 20
    var outline: Color = .white
    var outlineWidth: CGFloat = 1.75
    let glass: CGRect
    var glassRadius: CGFloat = 11
    let backlit: Bool
    let style: LCDStyle

    var body: some View {
        RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
            .fill(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
                    .strokeBorder(outline, lineWidth: outlineWidth)
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
            .fill(LinearGradient(colors: [style.glass, style.glass.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if backlit {
                    RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: style.backlightFalloff.map { style.backlight.opacity($0) },
                                startPoint: .leading, endPoint: .trailing))
                }
            }
            .frame(width: glass.width, height: glass.height)
            .offset(x: glass.minX, y: glass.minY)
    }
}
```

`body` returns two views; it is used inside the face's top-leading `ZStack`, which lays them out exactly as before.
- [ ] `CasioWatchFace.lcd` uses `LCDWindow(frame: CGRect(x: 89, y: 174, width: 414.5, height: 214), outline: Self.silver, glass: CGRect(x: 104, y: 191.5, width: 389.5, height: 184.5), backlit: backlit, style: style)`, `LCDText(...)` and `LiveSeconds(date:calendar:previewSeconds:glyph: 67, trailing: 486, baseline: 357.5, xScale: Self.digitSqueeze, style:)`; `style` is `LCDStyle()`; `Self.backlight` goes.
- [ ] Run tests; render (Task 3's harness uses the new API, so here only run the tests). Commit `refactor: Casio widget LCD parts`.

### Task 3: Model protocol and the F-91W model

**Files:** Create `SRC/CasioModel.swift`, `SRC/Models/F91W/CasioF91W.swift`, `SRC/Models/F91W/F91WFace.swift`. Delete `CasioWatchFace` from `SRC/CasioClockWidget.swift`.

- [ ] `CasioModel.swift`:

```swift
import SwiftUI

/// A Casio watch the package can draw as a widget. Each model lives in Models/<Name>/ and is
/// drawn on its own canvas, measured from a photo of the watch, with the kit and LCD parts.
protocol CasioModel {
    associatedtype Face: View
    associatedtype CaseBackground: View
    /// Stable WidgetKit kind; changing it removes the widget from people's Home Screens.
    static var kind: String { get }
    /// Name in the widget gallery ("Casio F-91W").
    static var displayName: String { get }
    /// Description in the widget gallery.
    static var summary: String { get }
    /// Canvas size in points (from the reference photo).
    static var canvas: CGSize { get }
    /// PostScript names of the fonts the model uses (all bundled in Resources/).
    static var fonts: [String] { get }
    /// Fills the widget behind the face (the case colour).
    static var caseBackground: CaseBackground { get }
    @ViewBuilder static func face(_ context: CasioFaceContext) -> Face
}

/// What a face shows: the time, the clock style and whether the light is on.
struct CasioFaceContext {
    var date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = DisplayParts.localeUses12HourClock
    var backlit = false
    /// Fixed seconds for static renders; the timer only animates inside a widget.
    var previewSeconds: Int? = nil
}

/// Every model, for tests (unique kinds, bundled fonts). Add new models here.
enum CasioModels {
    static let all: [any CasioModel.Type] = [CasioF91W.self]
}
```

- [ ] `Models/F91W/CasioF91W.swift`: `enum CasioF91W: CasioModel` with `kind = "CasioClockWidget"` (kept for placed widgets), `displayName = "Casio F-91W"`, `summary` = the current description string, `canvas = CGSize(width: 594, height: 530)`, `fonts = ["DSEG7Classic-BoldItalic", "DSEG14Classic-BoldItalic", "Michroma-Regular", "ArchivoExpanded-Black", "Saira-Medium", "SairaExpanded-SemiBold"]`, `caseBackground` = the `resin` gradient (lines 208-209), `face(_:)` returns `F91WFace(context: context)`. Also the palette (lines 210-216 minus backlight) as `static let`, `lcd = LCDStyle()`, `digitSqueeze`, and the four font helpers as `static func`.
- [ ] `Models/F91W/F91WFace.swift`: `struct F91WFace: View { let context: CasioFaceContext }` whose `body` is the top-leading `ZStack { bezel; printedFace; lcd }` — `bezel`, `frameLine`, `printedFace`, `bar`, `lcd` moved from `CasioWatchFace` with `Self.` → `CasioF91W.` and `date/calendar/...` → `context.…`. Header comment (lines 184-193) moves to `CasioF91W.swift`.
- [ ] Temporary render test `Tests/CasioClockWidgetTests/RenderPreviewTests.swift` (not committed):

```swift
import AppKit
import SwiftUI
import Testing

@testable import CasioClockWidget

@MainActor
@Test("render preview (temporary)")
func renderPreview() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 18, minute: 4, second: 56))!
    let late = cal.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 23, minute: 59, second: 8))!
    for (name, d, twelve, lit) in [("render", date, true, false), ("render-lit", date, true, true), ("render-24h", late, false, false), ("render-12", late, true, false)] {
        let ctx = CasioFaceContext(date: d, calendar: cal, uses12HourClock: twelve, backlit: lit, previewSeconds: name == "render-24h" ? 8 : 56)
        let view = FaceCanvas(size: CasioF91W.canvas) { CasioF91W.face(ctx) }
            .background(Color(white: 0.08))
            .frame(width: 594, height: 530)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let out = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("DevTemp/smarttube/scratch/measure/\(name).png")
        try rep.representation(using: .png, properties: [:])!.write(to: out)
    }
}
```

- [ ] Run `swift test … --filter renderPreview`, then for each of `render render-lit render-24h render-12`: `python3 samepixels.py before/$n.png $n.png` → `IDENTICAL`. If not, find the moved line that changed and fix it.
- [ ] Run all tests. Commit `refactor: Casio F-91W as the first CasioModel`.

### Task 4: Widget, provider and per-model light

**Files:** Create `SRC/Widget/CasioWatchWidget.swift`, `SRC/Widget/CasioClockProvider.swift`, `SRC/Widget/CasioBacklightIntent.swift`, `SRC/Models/F91W/CasioF91WWidget.swift`; delete `SRC/CasioClockWidget.swift`. Tests: `Tests/CasioClockWidgetTests/` split into `DisplayPartsTests.swift`, `TimelineTests.swift`, `ModelTests.swift`. App: `SmartTubeApp/DownloadWidget/DownloadLiveActivity.swift:144`.

- [ ] Failing tests first, `ModelTests.swift`:

```swift
import CoreText
import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Casio models")
struct ModelTests {
    @Test("kinds are unique; the F-91W keeps the original kind")
    func kinds() {
        let kinds = CasioModels.all.map { $0.kind }
        #expect(Set(kinds).count == kinds.count)
        #expect(CasioF91W.kind == "CasioClockWidget")
    }

    @Test("every model's fonts are bundled and register")
    func fonts() {
        BundledFonts.register()
        for model in CasioModels.all {
            for name in model.fonts {
                let font = CTFontCreateWithName(name as CFString, 12, nil)
                #expect(CTFontCopyPostScriptName(font) as String == name, "\(model.kind): \(name)")
            }
        }
    }

    @Test("the light is per model")
    func backlightPerModel() throws {
        let defaults = try #require(UserDefaults(suiteName: "CasioModelTests"))
        defaults.removePersistentDomain(forName: "CasioModelTests")
        let until = Date().addingTimeInterval(3)
        defaults.set(until, forKey: CasioBacklightIntent.defaultsKey(model: "A"))
        #expect(CasioBacklightIntent.backlightUntil(model: "A", defaults: defaults) == until)
        #expect(CasioBacklightIntent.backlightUntil(model: "B", defaults: defaults) == nil)
    }
}
```

- [ ] Run: fails to compile (`defaultsKey(model:)`, `backlightUntil(model:defaults:)` missing).
- [ ] `Widget/CasioBacklightIntent.swift`:

```swift
import AppIntents
import Foundation

/// Turns a model's LCD light on for a few seconds, like the watch's LIGHT button.
public struct CasioBacklightIntent: AppIntent {
    public static let title: LocalizedStringResource = "Casio Light"
    public static let description = IntentDescription("Lights up a Casio widget for a few seconds.")
    public static let isDiscoverable = false

    static let duration: TimeInterval = 3

    /// The model's widget kind.
    @Parameter(title: "Model")
    var model: String

    public init() {}

    init(model: String) {
        self.model = model
    }

    public func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget's timeline after a widget intent runs.
        UserDefaults.standard.set(Date().addingTimeInterval(Self.duration), forKey: Self.defaultsKey(model: model))
        return .result()
    }

    static func defaultsKey(model: String) -> String { "CasioClockWidget.backlightUntil.\(model)" }

    static func backlightUntil(model: String, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: defaultsKey(model: model)) as? Date
    }
}
```

- [ ] `Widget/CasioClockProvider.swift`: `CasioClockEntry` + `CasioClockProvider` (lines 64-104) moved; the provider gets `let model: String` and `getTimeline` reads `CasioBacklightIntent.backlightUntil(model: model)`. The static `entries`/`minuteEntries` stay unchanged.
- [ ] `Widget/CasioWatchWidget.swift`:

```swift
import AppIntents
import SwiftUI
import WidgetKit

// How it stays live:
// - Hours and minutes come from a timeline with one entry per minute (an hour of entries,
//   then WidgetKit asks for the next hour), so the display changes exactly on the minute.
// - Widgets can't redraw every second, so the seconds are WidgetKit's own timer text
//   counting up from the start of the minute, clipped to its last two digits (LiveSeconds).
// - Tapping the widget runs CasioBacklightIntent for that model: the LCD lights for 3 s.

/// The small Home Screen widget for one model. Internal: each model exposes a public wrapper
/// (see CasioF91WWidget) so the model protocol stays internal.
struct CasioWatchWidget<Model: CasioModel>: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Model.kind, provider: CasioClockProvider(model: Model.kind)) { entry in
            Button(intent: CasioBacklightIntent(model: Model.kind)) {
                FaceCanvas(size: Model.canvas) {
                    Model.face(CasioFaceContext(date: entry.date, backlit: entry.backlit))
                }
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { Model.caseBackground }
        }
        .configurationDisplayName(Model.displayName)
        .description(Model.summary)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
```

- [ ] `Models/F91W/CasioF91WWidget.swift`:

```swift
import WidgetKit

/// Casio F-91W: list `CasioF91WWidget()` in a WidgetBundle.
public struct CasioF91WWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration { CasioWatchWidget<CasioF91W>().body }
}
```

- [ ] Delete `SRC/CasioClockWidget.swift` (now empty). Move the existing tests into `DisplayPartsTests.swift` (the three formatting tests) and `TimelineTests.swift` (minute and backlight timeline tests); the old `fontIsBundled` test is replaced by `ModelTests.fonts`.
- [ ] App: `SmartTubeApp/DownloadWidget/DownloadLiveActivity.swift:144` `CasioClockWidget()` → `CasioF91WWidget()`.
- [ ] Run tests: all pass. Commit `refactor: generic Casio widget, light per model` (package + app line).

### Task 5: Docs

- [ ] README: package layout, `CasioF91WWidget()` in the WidgetBundle snippet, the four-step "Add a model" section from the spec (step 2 = public wrapper like `CasioF91WWidget`), remove line = `CasioF91WWidget()`.
- [ ] Package.swift comment: lists models and points to README (drop "its only resource is the generated LCD font").
- [ ] Spec: `caseBackground` is an associated `View` type; step 2 is the public wrapper. Commit `docs: Casio widget README for several models`.

### Task 6: Verify

- [ ] Run the fan schedule (`~/.claude/skills/fan-mode/fanmode schedule`), build the app (command in the private repo prompt / AGENTS), `git checkout -- SmartTubeApp/SmartTubeApp/Info-macOS.plist`.
- [ ] Install on "SmartTube Verify"; the Casio widget already on the Home Screen still shows (same kind); the gallery still lists "Casio F-91W"; a tap lights it (log: `CasioBacklightIntent` with the model parameter, lit entry).
- [ ] Update private task #356 with the restructure.
