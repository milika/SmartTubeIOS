# Architecture

## Layout

```
Sources/CasioClockWidget/
  CasioCatalogue.swift  the catalogue: CasioModels (registry), CasioWidgets (the public widgets),
                        CasioComplicationGallery. Registering a model happens only here.
  CasioModel.swift      CasioModel / CasioComplicationModel protocols, CasioFaceContext
  Widget/               the generic Home Screen widget and watch complication, the timeline
                        provider (a thin WidgetKit adapter), the light intent
  LiveClock/            the live clock: entry schedule, timer start, LiveHoursMinutes,
                        LiveSeconds, TimerDigit
  LCD/                  LCDPanel (window + display + light), LCDStyle (fonts, glass, ink, light,
                        shadow), LCDText, LCDWindow, LCDFont,
                        DisplayParts (the strings a display shows), DotMatrixText, LCDMarks, and
                        the module displays (LCDModuleDisplay)
  Kit/                  FaceCanvas + place(...) modifiers, InkText, CaseFont, BundledFonts,
                        shapes (CutCornerRect, Pointer, BrickPattern), text effects
  Models/<Name>/        one folder per watch: the model (palette, LCD style, preview) and its face
  Resources/            the fonts and their licences
Tests/CasioClockWidgetTests/   unit, contract, catalogue, font, render and manifest tests; the
                               opt-in reference render (docs/ADDING-A-MODEL.md)
references/<Model>.json         each model's reference manifest: archived image, canvas mapping,
                                the time it shows, masks, measured elements (no images)
tools/casio_measure.py          measuring faces against their reference images (`check <manifest>`)
docs/                           this file, ADDING-A-MODEL.md (the method), REFERENCES.md
```

Vocabulary (also in the repository's `CONTEXT.md`): a **watch model** is one Casio watch the
package draws; the **catalogue** is the one list of what the package publishes; an **LCD module**
is Casio's numbered display, shared by several watches, and its **module display** is that LCD's
layout, drawn once; the **face** draws the case around it; the **live clock** is how the time
stays live.

## Faces and canvases

Each model draws its face on its own canvas, in points measured from its reference image
([REFERENCES.md](REFERENCES.md)). `FaceCanvas` scales the model's `widgetArea` (a square part of
the canvas) to the widget. Faces that are wider than tall extend their case (`caseExtension`) so
the square widget is filled without stretching anything; `CaseExtension` shares the extra height
out by band (case, window, side labels, print below), and a face moves each group into its band.

Printed labels are `InkText`: the label's glyph outlines in a free stand-in font, stretched to
fill the ink box measured on the reference, so font metrics don't move them.

## Displays (LCD modules)

A face draws only the case and an `LCDPanel` (the window, its glass and light, and the display).
The characters come from its module's display, an `LCDModuleDisplay` measured once: its `glass` is
the measured window and `canvasOrigin` where that window sat on the reference canvas, and
`placed(in:)` puts it in any watch's glass (scaled to its width, centred vertically). Each display
declares its measured lines of characters as `LCDRun` values (`static let runs`: glyph height,
anchored edge, baseline, squeeze, tracking, colon gap), so the numbers live in one table and a test
checks that every run sits inside its glass.

The same module can look different through two watches' windows: the F-91W and A158W both have
module 593, but the A158W's digits read narrower, so `Module593Layout` (where module 593's
characters sit) has two measured instances, `Module593Display` (F-91W) and `A158WDisplay`. The
F-91W complication uses `Module593Complication`, a compact layout for the 200 × 80 complication
slot.

Fixed marks shared by displays are in `LCDMarks.swift` (the hourly signal "D" with arcs, the
alarm bell); `DotMatrixText` draws dot-matrix characters in three glyph sets (rounded 5×7 for the
GMW-B5000's date, bold and slanted for the GW-B5600's, 5×5 blocks for the DBC-32's weekday).

`LCDStyle` holds a display's look: DSEG segment fonts, glass and ink colours, the light
(colour and left-to-right falloff), an optional faint unlit-segment layer (off on every model), the
shadow (`LCDShadow`: the frame's shadow on the glass edge and the segments' faint shadow on the
reflector), and `litInk` for **inverted (negative) displays** (W-738H): lit, the segments take
that colour and the dark glass stays dark.

## How the time stays live

WidgetKit only redraws a widget at its timeline entries, so `LiveClock/` combines two things
(the contract is written out at the top of `LiveClock.swift`):

- **Hours, date, weekday, PM / 24H** come from the entry on screen. The timeline has one entry at
  every hour start, 12 at a time; then WidgetKit asks for more.
- **Minutes and seconds** come from one WidgetKit timer text, `Text(start, style: .timer)`, which
  animates itself. It starts 10 hours before the entry's hour, so it always reads "10:MM:SS" with
  the current minutes and seconds; `LiveHoursMinutes` and `LiveSeconds` show the digits they need
  through clipped windows.
- **Digit spacing:** when a module's digits sit closer or further apart than DSEG's cells
  (`tracking`), each live digit is its own `TimerDigit` window onto the untracked timer text, so
  the clipping stays exact. Digits switch instantly (`contentTransition(.identity)`), like
  segments, instead of WidgetKit's rolling-digit animation.
- **Why not a minute timeline:** WidgetKit stores each entry fully drawn; a minute timeline of a
  detailed face reached 36 MB and was rejected. Hourly entries keep it to a few MB.
- **The light:** tapping a widget runs `CasioBacklightIntent` for that model only; the provider
  returns a lit entry now, an unlit one 3 s later and two hourly entries, then reloads (a short
  timeline renders quickly, so the light shows right after the tap).
- **12- or 24-hour** follows the device setting, as the watches do (PM, P or 24H marks).
- **Steps** (`Steps/CasioSteps.swift`): a model with `usesSteps` (the ABL-100WE) gets today's
  step count from the Health app in its entries, toward a 10,000-step goal. The app asks for
  read access (Settings > Widgets; a widget can't show Health's sheet) and reloads the widget
  when it comes to the foreground. The provider reads Health when it builds the timeline and
  remakes it every 30 minutes; Health is encrypted while the iPhone is locked, so the last read
  of the day is kept and used until a new one succeeds.

## The catalogue

`CasioCatalogue.swift` is the only place a model is registered: `CasioModels.all` (tests iterate
it) and `CasioWidgets.homeScreen` (a `WidgetBundleBuilder` the app's widget extension lists). Watch
complications: `CasioModels.complications` and `CasioWidgets.complications`, listed by the watch
extension; `CasioComplicationGallery` previews them in the watch app. `CatalogueTests` fails if the
two lists disagree. A model's `kind` is permanent: it identifies the widgets people placed (the
F-91W's is `"CasioClockWidget"`, from when it was the only model).

## Tests

`swift test` in the package folder:

- display strings (`DisplayPartsTests`), dot-matrix glyphs in both sets, weekday letters;
- the live-clock contract (`TimelineTests`): at every minute of a plain and a lit timeline, across
  a DST change and a half-hour UTC offset, the right hour and "10:MM:SS"; timer frames fit
  "10:59:59"; timer-digit window offsets;
- models: unique kinds, the light per model; fonts: the bundled files are exactly the fonts in use
  and all register; catalogue: every registered model is published;
- rendering: every model draws its face and its light changes it; every module display renders
  alone and differs between 12- and 24-hour time; every display's runs sit inside its glass;
- manifests (`ManifestTests`): every registered model has a reference manifest naming it, with
  its elements on its canvas;
- the case extension: bands move top to bottom, and the reference layout leaves it out.

Faces themselves are checked against their reference images with
`tools/casio_measure.py check references/<Model>.json`: every element and the LCD window within
1.5 pt (needs the archived images; see [ADDING-A-MODEL.md](ADDING-A-MODEL.md)). The repository's
`.improve/` holds a golden-render harness for refactoring shared code (the faces must render
pixel-identical).
