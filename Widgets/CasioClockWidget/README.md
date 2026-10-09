# CasioClockWidget (experimental)

Small Home Screen widgets: live digital clocks drawn as Casio watches, one widget per model, all
published together as `CasioWidgets.homeScreen`:

- **F-91W** (`CasioF91W`): black resin case, blue bezel lines, gold labels, grey-green
  LCD with seven-segment digits, day/date, PM marker, running seconds. Also an Apple Watch
  complication.
- **A158W** (`CasioA158W`): the same LCD module in a chrome case with a black face, a
  steel-blue octagon line and a WATER RESIST band.
- **G-Shock GMW-B5000** (`CasioGMWB5000`): the black face inside the steel bezel (the
  widget leaves the bezel out), brick pattern, blue-grey LCD with PS / RCVD / DST marks and a dot-matrix date
  (drawn as shapes; day or month first, following the device's date order).
- **G-Shock DW-5000C** (`CasioDW5000C`): the first G-Shock (1983): black face with a red
  octagon line and bricks, gold and teal print, beige LCD in a silver frame, month-first date in
  a box; its bulb lights the display warm yellow.
- **W-59** (`CasioW59`): black resin, a blue band between two white lines, gold and red print,
  the module-590 display (its own layout of 24H, weekday, date, H:MM and seconds).

Self-contained Swift package — no
dependencies on any app code. Its resources are fonts, all under the SIL Open Font License 1.1
(licenses in `Resources/`):

- LCD: DSEG7 / DSEG14 Classic Bold Italic by Keshikan (keshikan.net).
- Printed text (all models), free look-alikes of the watch's typefaces (Google Fonts): Michroma for
  Microgramma / Eurostile Extended, Archivo Expanded Black (a static instance of Archivo's
  variable font, wght 900 / wdth 125) for Neue Helvetica Extended Black, Saira Medium for
  Eurostile Medium, and Saira Expanded SemiBold (a static instance of Saira's variable font,
  wght 600 / wdth 125, stretched) for the "WR" mark. Subset to the characters the face uses.

Every LCD has the same depth (`LCDShadow` in `LCDStyle`): the frame shades the glass's top and
left edge, and the segments cast a faint shadow on the reflector behind them.

Tap a widget for the backlight (an `AppIntent`, iOS 17 interactive widgets): that model's LCD
lights for 3 seconds (the F-91W glows green from the left, like its LED).

Each face is laid out on a canvas measured from a front-on photo of the real watch. The faces
are wider than tall, so their case is extended to fill the square widget (every element keeps
its measured size; the groups spread apart). F-91W: Wikimedia Commons `Casio_F-91W_5051.jpg`;
typefaces per Fonts In Use (fontsinuse.com/uses/74290). A158W: Wikimedia Commons `A158W.jpg`.
GMW-B5000: Wikimedia Commons `Wikipedia-Casio-G-Shock-Edelstahl-800.jpg`. DW-5000C:
Wikimedia Commons `DW-5000.jpg`; W-59: Wikimedia Commons `Casio W-59 digital watch.jpg`
(public domain); its printed labels are `InkText`, glyph outlines stretched to
the ink boxes measured on the photo. Known difference: the DW-5000C draws a double-width W in
the weekday; DSEG14's W is single width.

## Add to a project

1. Add this folder as a local package (Xcode: File > Add Package Dependencies… > Add Local…).
2. Link the `CasioClockWidget` library to your **widget extension** target.
3. List the catalogue in the extension's `WidgetBundle` (every model; new models appear without
   touching the app):

   ```swift
   import CasioClockWidget

   @main
   struct MyWidgets: WidgetBundle {
       var body: some Widget {
           CasioWidgets.homeScreen
       }
   }
   ```

Requires iOS 17 / macOS 14 (uses `containerBackground` and `contentMarginsDisabled`).

### Apple Watch complication

Apps can't make watch faces; models with a complication (`CasioComplicationModel`) provide a
rectangular one for Apple's faces (Modular, Modular Duo, Infograph Modular) and the Smart Stack:
the LCD with day/date, H:MM and live seconds — grey-green glass on full-colour faces, the face's
tint on tinted ones. No light (complications can't run a tap action). watchOS 10. List it in a
watchOS widget extension inside a watch app:

```swift
@main
struct CasioComplications: WidgetBundle {
    var body: some Widget {
        CasioWidgets.complications
    }
}
```

`CasioComplicationGallery()` shows every complication live, with its name, for the watch app's
own screen. In SmartTube:
`SmartTubeApp/Watch` (watch app) and `SmartTubeApp/WatchComplications` (extension).

## Remove

Delete the `CasioWidgets…` lines and the package dependency.

## Layout

```
Sources/CasioClockWidget/
  CasioCatalogue.swift  the catalogue: CasioModels (registry), CasioWidgets (public widgets),
                     CasioComplicationGallery; registering a model happens only here
  CasioModel.swift   CasioModel / CasioComplicationModel protocols, CasioFaceContext
  Widget/            generic widget + watch complication widget, timeline provider (WidgetKit
                     adapter), light intent
  LiveClock/         the live clock: entry schedule, timer start, LiveHoursMinutes, LiveSeconds
  LCD/               DSEG fonts, LCDStyle, LCDText, LCDWindow, DisplayParts,
                     DotMatrixText (5×7 dot-matrix characters, drawn as shapes), and the module
                     displays (LCDModuleDisplay): Module593Display (F-91W, A158W, A168W…) and its
                     compact Module593Complication, Module3459Display (GMW-B5000, GW-B5600…),
                     Module240Display (DW-5000C), Module590Display (W-59)
  Kit/               FaceCanvas + place(...) modifiers, CaseFont, BundledFonts, shapes (incl. the
                     G-Shock BrickPattern), text effects, InkText (a label filling a measured ink box)
  Models/F91W/       the F-91W: model (palette, LCD style, Xcode previews), face, complication
  Models/A158W/      the A158W: model, face
  Models/GMWB5000/   the G-Shock GMW-B5000: model, face
  Models/DW5000C/    the G-Shock DW-5000C: model, face
  Models/W59/        the W-59: model, face
  Resources/         fonts and their licences (all models)
```

## Add a model

1. Measure a front-on photo of the watch and pick its canvas size. Add
   `Models/<Name>/Casio<Name>.swift`, an `enum` implementing `CasioModel` (kind, gallery name
   and description, canvas, case background, `face(_:)`, optionally `widgetArea`: the part
   of the canvas the square widget shows), and its face view: the case drawn with `place(...)`,
   the case-font helpers (`Casio<Name>.michroma(size)`, …), `InkText` and the shapes, then an
   `LCDWindow` with its module's display placed in the glass (see below; a new module's display
   uses `LCDText`, `LiveHoursMinutes`, `LiveSeconds`, `context.displayParts(blankDigit:)`), and
   its own `LCDStyle`. A new font goes into `Resources/`
   with its licence, and its PostScript name into `CaseFont` (the only place names are spelled).
2. Register it in `CasioCatalogue.swift`: the model in `CasioModels.all` (tests check unique
   kinds and that it renders) and `CasioWatchWidget<Casio<Name>>()` in `CasioWidgets.homeScreen`.
   The app picks it up with no change. Copy the `#Preview` at the end of `CasioF91W.swift` to tune
   the face live in Xcode's canvas.
3. Optional Apple Watch complication: conform to `CasioComplicationModel` (complication kind,
   name, summary, `rectangularComplication(_:)`, see `Models/F91W/F91WComplication.swift`), and
   register it in `CasioModels.complications` and `CasioWidgets.complications`; the watch app's
   gallery and the watch extension pick it up.

Watches that share a Casio module share its display: a face draws only the case and places its
module's display (an `LCDModuleDisplay`, in `LCD/`) in its glass with `placed(in:)`. A model with a
known module needs no display work; a new module gets its own `Module<number>Display`, measured
once from a photo.

A model's `kind` must never change once shipped: it identifies the widgets people placed. (The
F-91W's is `"CasioClockWidget"`, from when it was the only model.)

## How it stays live

One module, `LiveClock/`, owns all of it: the entry schedule, the timer start, the two live
views and the contract between them (written out at the top of `LiveClock.swift`); the widget's
timeline provider only hands the schedule to WidgetKit.

- Hours, date, weekday, PM / 24H: a timeline with one entry per hour (12 at a time).
- Minutes and seconds: one `Text(date, style: .timer)` started 10 hours before the hour, so it
  reads "10:MM:SS"; `LiveHoursMinutes` shows its minutes and `LiveSeconds` its last two digits
  Widgets can't redraw every second, but timer text animates itself.
  A timeline of minute entries stores a full drawing per minute; for a detailed face (the
  GMW-B5000) that grew to 36 MB and WidgetKit rejected it. Hourly entries keep it to a few MB.
- The light: a lit entry for 3 s, then two hourly entries and a reload (a short lit timeline
  renders fast, so the light shows right after the tap).
- 12- or 24-hour follows the device setting; 12-hour shows the hour without a leading zero
  and a PM marker, 24-hour shows "24H", like the watch.

## Tests

`swift test` in this folder: formatting, the live-clock contract (at every minute of a timeline
the right hour and "10:MM:SS", across a DST change; timer frames fit "10:59:59"), models (unique kinds, the light per
model), fonts (the bundled files are exactly `CaseFont.all` plus DSEG, and they register), and
rendering (every model draws its face and its light changes it).
