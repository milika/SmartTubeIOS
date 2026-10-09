# CasioClockWidget (experimental)

Small Home Screen widgets: live digital clocks drawn as Casio watches, one widget per model.
Today the **F-91W** (black resin case, blue bezel lines, gold labels, grey-green LCD with
seven-segment digits, day/date, PM marker, running seconds). Self-contained Swift package — no
dependencies on any app code. Its resources are fonts, all under the SIL Open Font License 1.1
(licenses in `Resources/`):

- LCD: DSEG7 / DSEG14 Classic Bold Italic by Keshikan (keshikan.net).
- F-91W printed text, free look-alikes of the watch's typefaces (Google Fonts): Michroma for
  Microgramma / Eurostile Extended, Archivo Expanded Black (a static instance of Archivo's
  variable font, wght 900 / wdth 125) for Neue Helvetica Extended Black, Saira Medium for
  Eurostile Medium, and Saira Expanded SemiBold (a static instance of Saira's variable font,
  wght 600 / wdth 125, stretched) for the "WR" mark. Subset to the characters the face uses.

Tap a widget for the backlight (an `AppIntent`, iOS 17 interactive widgets): that model's LCD
lights for 3 seconds (the F-91W glows green from the left, like its LED).

Each face is laid out on a canvas measured from a front-on photo of the real watch. F-91W:
Wikimedia Commons `Casio_F-91W_5051.jpg`; typefaces per Fonts In Use (fontsinuse.com/uses/74290).

## Add to a project

1. Add this folder as a local package (Xcode: File > Add Package Dependencies… > Add Local…).
2. Link the `CasioClockWidget` library to your **widget extension** target.
3. List the models you want in the extension's `WidgetBundle`:

   ```swift
   import CasioClockWidget

   @main
   struct MyWidgets: WidgetBundle {
       var body: some Widget {
           CasioF91WWidget()
       }
   }
   ```

Requires iOS 17 / macOS 14 (uses `containerBackground` and `contentMarginsDisabled`).

## Remove

Delete the `Casio…Widget()` lines and the package dependency.

## Layout

```
Sources/CasioClockWidget/
  CasioModel.swift   CasioModel protocol, CasioFaceContext, CasioModels.all
  Widget/            generic widget, timeline provider, the light intent (per model)
  LCD/               DSEG fonts, LCDStyle, LCDText, LiveSeconds, LCDWindow, DisplayParts
  Kit/               FaceCanvas + place(...) modifiers, CaseFont, BundledFonts, shapes, text effects
  Models/F91W/       the F-91W: model (palette, fonts, LCD style), face layout, public widget
  Resources/         fonts and their licences (all models)
```

## Add a model

1. Measure a front-on photo of the watch and pick its canvas size. Add
   `Models/<Name>/Casio<Name>.swift`, an `enum` implementing `CasioModel` (kind, gallery name
   and description, canvas, fonts, case background, `face(_:)`), and its face view drawn with
   `place(...)`, `CaseFont`, the shapes and the LCD parts (`LCDWindow`, `LCDText`,
   `LiveSeconds`, `DisplayParts`, its own `LCDStyle`). Add its fonts and licences to `Resources/`.
2. Add a public wrapper next to it, like `Models/F91W/CasioF91WWidget.swift`:

   ```swift
   public struct Casio<Name>Widget: Widget {
       public init() {}
       public var body: some WidgetConfiguration { CasioWatchWidget<Casio<Name>>().body }
   }
   ```
3. Add the model to `CasioModels.all` (tests check unique kinds and bundled fonts).
4. List `Casio<Name>Widget()` in the app's `WidgetBundle`.

A model's `kind` must never change once shipped: it identifies the widgets people placed. (The
F-91W's is `"CasioClockWidget"`, from when it was the only model.)

## How it stays live

- Hours and minutes: a timeline with one entry per minute (an hour at a time).
- Seconds: `Text(date, style: .timer)` counting up from the start of the minute, clipped to
  its last two digits — widgets can't redraw every second, but timer text animates itself.
- The light: a lit entry for 3 s, then three minutes of entries and a reload (a short lit
  timeline renders fast, so the light shows right after the tap).
- 12- or 24-hour follows the device setting; 12-hour shows the hour without a leading zero
  and a PM marker, 24-hour shows "24H", like the watch.

## Tests

`swift test` in this folder: formatting, timeline entries, and models (unique kinds, every
model's fonts bundled, the light per model).
