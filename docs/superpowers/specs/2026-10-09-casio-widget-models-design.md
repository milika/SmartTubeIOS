# Casio widget: several watch models — design

Date: 2026-10-09. Package: `Widgets/CasioClockWidget/`. Status: approved (owner, approach A).

## Goal

Restructure the experimental Casio F-91W widget package so more Casio models can be added
easily. Planned next: A158W / A168W, W-800H, G-Shock DW-5600, more later. These differ a lot
(case shape, bezel print, LCD layout, fonts), so a model is code built from shared parts, not
a data file. The package stays self-contained: no dependency on app code.

Out of scope: the Apple Watch app and complication (a separate design, which reuses this kit);
new models; any visual change to the F-91W.

## Decisions

- **Approach A:** a shared kit plus one Swift file (folder) per model. Colours and label lists
  are plain data inside the model where that reads naturally.
- **One widget per model** (owner's choice): each model is its own entry in the widget gallery.
- **The F-91W keeps widget kind `"CasioClockWidget"`**, so widgets already on Home Screens
  survive the update.
- **The tap light is per model:** tapping one model lights only widgets of that model.
- **Models are internal to the package.** Public API: one widget type per model
  (`CasioF91WWidget`, a small wrapper around the internal generic `CasioWatchWidget<Model>`, so
  the protocol can stay internal) and the backlight intent. Opening the kit to other packages
  can come later.
- **No UIKit/AppKit in the kit or models**, so the watchOS part can reuse them. The watchOS
  platform itself is added with the watch work.

## Structure

```
Sources/CasioClockWidget/
  CasioModel.swift          protocol CasioModel + CasioFaceContext
  Widget/
    CasioWatchWidget.swift   internal generic Widget<Model>
    CasioClockProvider.swift generic timeline provider (minute entries, short lit timeline)
    CasioBacklightIntent.swift  intent with a `model` parameter; per-model defaults key
  LCD/
    LCDFont.swift            DSEG font metrics + registration (from today's LCDFont)
    LCDStyle.swift           glass, ink, unlit opacity, digit/letter fonts, backlight colour
    LCDText.swift            text with faint unlit segments, tracking, x-squeeze
    LiveSeconds.swift        timer text clipped to two digits
    LCDWindow.swift          frame, glass, backlight glow
    DisplayParts.swift       time/date formatting (12/24 h, weekday, blank digits)
  Kit/
    FaceCanvas.swift         fixed-canvas container scaled to the widget + place(...) modifiers
    BundledFonts.swift       registers every bundled font once
    CaseFont.swift           custom(postScriptName, size)
    TextEffects.swift        emboldened, oblique
    Shapes.swift             CutCornerRect, Pointer
  Models/F91W/
    CasioF91W.swift          the model: palette, fonts, LCD style
    F91WFace.swift           the measured layout (today's face)
    CasioF91WWidget.swift    public widget wrapper
  Resources/                 fonts + licences (unchanged; all models' fonts live here)
```

### CasioModel

```swift
protocol CasioModel {
    associatedtype Face: View
    static var kind: String { get }            // stable widget kind
    static var displayName: String { get }     // "Casio F-91W"
    static var summary: String { get }         // gallery description
    static var canvas: CGSize { get }          // measured from the reference photo
    associatedtype CaseBackground: View
    static var caseBackground: CaseBackground { get } // container background
    @ViewBuilder static func face(_ context: CasioFaceContext) -> Face
}

struct CasioFaceContext {
    var date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool
    var backlit = false
    var previewSeconds: Int? = nil   // static renders; the timer only animates in a widget
}
```

The internal `CasioWatchWidget<Model>` builds the `StaticConfiguration`: `Button(intent:
CasioBacklightIntent(model: Model.kind))` around `FaceCanvas(Model.canvas) { Model.face(ctx) }`,
`supportedFamilies([.systemSmall])`, `contentMarginsDisabled()`.

### Adding a model (README gets this section)

1. Add `Models/<Name>/Casio<Name>.swift` implementing `CasioModel`, drawn on its own measured
   canvas with kit parts. Add its fonts and licences to `Resources/`.
2. Add a public wrapper `Casio<Name>Widget: Widget` whose body is `CasioWatchWidget<Casio<Name>>().body`.
3. List `Casio<Name>Widget()` in the app's `WidgetBundle`.
4. Add the model to `CasioModels.all` (tests check unique kinds and bundled fonts).

## Behaviour that must not change

- F-91W looks identical: the macOS render after the restructure equals the one before, pixel
  for pixel (same `fine.py` measurements).
- Timeline: one entry per minute for an hour; after a tap, a lit entry for 3 s from timeline
  build time, then 3 minutes of entries, then a reload.
- 12/24-hour formatting as today.

## Testing

- Existing tests move with the code and keep passing.
- New: every model's kind is unique and the F-91W kind is `"CasioClockWidget"`; the backlight
  key differs per model and a tap on one model does not light another's timeline.
- Manual: render the F-91W before/after and compare pixels; build the app and check the widget
  on the "SmartTube Verify" simulator (still in the gallery and on the Home Screen).
