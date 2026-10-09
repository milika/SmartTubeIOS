# CasioClockWidget (experimental)

Small Home Screen widgets: live digital clocks drawn as Casio watches, one widget per model:

- **F-91W** (`CasioF91WWidget`): black resin case, blue bezel lines, gold labels, grey-green
  LCD with seven-segment digits, day/date, PM marker, running seconds. Also an Apple Watch
  complication.
- **A158W** (`CasioA158WWidget`): the same LCD module in a chrome case with a black face, a
  steel-blue octagon line and a WATER RESIST band.
- **G-Shock GMW-B5000** (`CasioGMWB5000Widget`): the black face inside the steel bezel (the
  widget leaves the bezel out), brick pattern, blue-grey LCD with PS / RCVD / DST marks and a dot-matrix date
  (drawn as shapes; day or month first, following the device's date order).
- **G-Shock DW-5000C** (`CasioDW5000CWidget`): the first G-Shock (1983): black face with a red
  octagon line and bricks, gold and teal print, beige LCD in a silver frame, month-first date in
  a box; its bulb lights the display warm yellow.

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
Wikimedia Commons `DW-5000.jpg`; its printed labels are `InkText`, glyph outlines stretched to
the ink boxes measured on the photo. Known difference: the DW-5000C draws a double-width W in
the weekday; DSEG14's W is single width.

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
           CasioA158WWidget()
           CasioGMWB5000Widget()
           CasioDW5000CWidget()
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
        CasioF91WComplication()
    }
}
```

`CasioF91WComplicationPreview()` is the same view for the watch app's own screen. In SmartTube:
`SmartTubeApp/Watch` (watch app) and `SmartTubeApp/WatchComplications` (extension).

## Remove

Delete the `Casio…Widget()` lines and the package dependency.

## Layout

```
Sources/CasioClockWidget/
  CasioModel.swift   CasioModel protocol, CasioFaceContext, CasioModels.all
  Widget/            generic widget + watch complication widget, timeline provider, light intent
  LCD/               DSEG fonts, LCDStyle, LCDText, LiveSeconds, LCDWindow, DisplayParts,
                     Module593Display (the shared display of module 593: F-91W, A158W, A168W…),
                     DotMatrixText (5×7 dot-matrix characters, drawn as shapes)
  Kit/               FaceCanvas + place(...) modifiers, CaseFont, BundledFonts, shapes (incl. the
                     G-Shock BrickPattern), text effects, InkText (a label filling a measured ink box)
  Models/F91W/       the F-91W: model (palette, fonts, LCD style), face, complication, public widgets
  Models/A158W/      the A158W: model, face, public widget
  Models/GMWB5000/   the G-Shock GMW-B5000: model, face, public widget
  Models/DW5000C/    the G-Shock DW-5000C: model, face, public widget
  Resources/         fonts and their licences (all models)
```

## Add a model

1. Measure a front-on photo of the watch and pick its canvas size. Add
   `Models/<Name>/Casio<Name>.swift`, an `enum` implementing `CasioModel` (kind, gallery name
   and description, canvas, fonts, case background, `face(_:)`, optionally `widgetArea`: the part
   of the canvas the square widget shows), and its face view drawn with
   `place(...)`, the case-font helpers (`Casio<Name>.michroma(size)`, …), `InkText`, the shapes
   and the LCD parts (`LCDWindow`, `LCDText`, `LiveHoursMinutes`, `LiveSeconds`,
   `context.displayParts(blankDigit:)`, its own `LCDStyle`). A new font goes into `Resources/`
   with its licence, and its PostScript name into `CaseFont` (the only place names are spelled).
2. Add a public wrapper next to it, like `Models/F91W/CasioF91WWidget.swift`:

   ```swift
   public struct Casio<Name>Widget: Widget {
       public init() {}
       public var body: some WidgetConfiguration { CasioWatchWidget<Casio<Name>>().body }
   }
   ```
3. Add the model to `CasioModels.all` (tests check unique kinds and bundled fonts), and copy the
   `#Preview` from `CasioF91WWidget.swift` to tune the face live in Xcode's canvas.
4. List `Casio<Name>Widget()` in the app's `WidgetBundle`.
5. Optional Apple Watch complication: conform to `CasioComplicationModel` (complication kind,
   name, summary, `rectangularComplication(_:)`, see `Models/F91W/F91WComplication.swift`), add a
   public wrapper like `CasioF91WComplication`, add it to `CasioModels.complications`, and list it
   in the watch extension's `WidgetBundle`.

Watches that share a Casio module share its display: draw it once (like `Module593Display`) and
place it in each model's glass, rather than measuring it again from each photo.

A model's `kind` must never change once shipped: it identifies the widgets people placed. (The
F-91W's is `"CasioClockWidget"`, from when it was the only model.)

## How it stays live

- Hours, date, weekday, PM / 24H: a timeline with one entry per hour (12 at a time).
- Minutes and seconds: one `Text(date, style: .timer)` started 10 hours before the hour, so it
  reads "10:MM:SS"; `LiveHoursMinutes` shows its minutes and `LiveSeconds` its last two digits
  (see `LCD/LiveClock.swift`). Widgets can't redraw every second, but timer text animates itself.
  A timeline of minute entries stores a full drawing per minute; for a detailed face (the
  GMW-B5000) that grew to 36 MB and WidgetKit rejected it. Hourly entries keep it to a few MB.
- The light: a lit entry for 3 s, then two hourly entries and a reload (a short lit timeline
  renders fast, so the light shows right after the tap).
- 12- or 24-hour follows the device setting; 12-hour shows the hour without a leading zero
  and a PM marker, 24-hour shows "24H", like the watch.

## Tests

`swift test` in this folder: formatting, timeline entries, and models (unique kinds, every
model's fonts bundled, the light per model).
