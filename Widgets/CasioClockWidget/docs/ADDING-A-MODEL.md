# Adding a model

The method every watch in this package follows. The goal is a face as close as possible to the
real watch, and the proof is a check, not an impression:

- every printed label, mark and display character within **1.5 pt** of the reference image, and
  the LCD window's edges too;
- colours sampled from a photo of a real watch;
- no element invented, none left out (except the G-Shock bezels, by decision).

A model is done when `python3 tools/casio_measure.py check references/<Name>.json` reports
**0 elements off** and the review in step 9 finds nothing more.

Tools: `tools/casio_measure.py` (Python 3 with Pillow, NumPy and SciPy), the opt-in render test
`ReferenceRenderTests` and the manifest test `ManifestTests`. Reference images, canvases and
renders stay outside the repository (for example `~/DevTemp/smarttube/scratch/ref-<model>/`);
images are measured only, never shipped or committed.

## Overview

| Step | Result |
|---|---|
| 1. Reference | an archived, front-on image and its row in REFERENCES.md |
| 2. Canvas | the mapping from image pixels to canvas points |
| 3. Manifest | `references/<Name>.json`: image, mapping, time shown, masks, every element |
| 4. Measure | ink boxes, window edges, digit runs and colours, in canvas points |
| 5. Model and face | `Models/<Name>/`: case, print as measured `InkText`, an `LCDPanel` |
| 6. Display | the LCD: an existing module display or a new one, its runs and marks |
| 7. Register | the catalogue, so the widget appears |
| 8. Check | `casio_measure.py check` until it reports 0 elements off |
| 9. Review and ship | side-by-side review, tests, simulator, docs |

## 1. Find a reference image

A straight, front-on, sharp image of the real watch, the larger the better: see
[REFERENCES.md](REFERENCES.md#finding-new-references) for where to look and the licence rules.
Product renders are fine for geometry; take colours from a photo of a real watch when you can (the
A168W's come from one). Archive the image in the NAS folder (file name: model, then source) and
add its row to REFERENCES.md.

## 2. Map it onto a canvas

Pick an origin in image pixels and a canvas size in points that holds the watch's face (and any
case print you keep). One image pixel per point is fine; `--scale` handles very large or small
images, `--rotate` levels a tilted photo. Phone photos stored on their side are turned upright by
their EXIF orientation first, and images with a transparent background are put on white. A phone's lens bows long straight lines near the photo's edges (the
DBC-32's keypad rules by up to 5 pt): draw them straight and say so in the manifest's `notes`.

```bash
python3 tools/casio_measure.py canvas ref.png 540 580 860 700 --out ref-dir
```

`grid.png` shows a 10 pt grid over the image. Write the mapping in the model's header comment, in
REFERENCES.md and in the manifest.

## 3. Write the manifest first

The manifest, `references/<Name>.json`, is the model's measuring record: whatever you measure goes
in it, so the face can be checked again at any time (`ManifestTests` makes sure every registered
model has one and that its boxes lie on its canvas).

```json
{
  "model": "Casio<Name>",
  "image": "<Name> - owner, <description> (measured).jpg",
  "canvas": {"origin": [540, 580], "scale": 1, "rotate": 0, "size": [860, 700]},
  "time": "2024-06-30T22:58:50",
  "twelveHour": true,
  "masks": {"print": {"lum": [80, null], "sat": [null, 40]}},
  "notes": ["Why an element is measured the way it is."],
  "elements": [
    {"name": "CASIO", "mask": "white", "box": [360, 140, 505, 175]},
    {"name": "TOUGH SOLAR", "mask": "print", "renderMask": "white", "box": [272, 98, 440, 115]},
    {"name": "LCD glass", "mask": "glass", "box": [235, 238, 638, 497], "kind": "edges"}
  ]
}
```

- **time**: exactly what the image's LCD shows (weekday, date, time, seconds), and `twelveHour`
  if it shows P / PM. `timeZone` (for example `"Europe/Berlin"`) makes daylight-saving indicators
  such as DST show, as on the GMW-B5000's photo.
- **elements**: everything printed or shown. List every label, logo, mark, dot and pointer; each
  LCD line (weekday, date, time, seconds) and icon; and the LCD glass as an `edges` element.
- **boxes**: each box holds its element with a margin of 1–3 pt and nothing else. Watch for
  neighbours (arrows next to labels, case lines beside vertical print, frame lines inside the LCD)
  and for the shadow photos often have along the top of the LCD.
- **masks**: the default masks are `white`, `dark`, `light`, `gold`, `red` and `blue`. A manifest
  can define its own as thresholds (`lum`, `sat`, `r`, `g`, `b`, differences such as `"r-b"`,
  absolute ones such as `"|r-b|"`). Use `renderMask` when the face's colour differs from the
  image's on purpose: colours taken from a real photo, or print brightened because the photo is
  dark.
- **notes**: why an element is measured the way it is, above all the font limitations below.
- `renderOffset` is for a canvas larger than the reference's (the CA-53W's side padding).

## 4. Measure

On `photo-canvas.png` (from step 2, or `check --out`):

- **Ink boxes**: `casio_measure.py boxes photo-canvas.png spec.json` with a list of elements in
  the manifest's format.
- **LCD digits**: `casio_measure.py runs photo-canvas.png X0 Y0 X1 Y1` prints one ink run per
  character, so you get each glyph's width and the pitch between characters.
- **The LCD window**: brightness profiles across the four edges, where the glass meets the frame.
  A photo often shades the glass near the frame, so the edge is where the glass leaves the dark
  surround, not where it reaches full brightness.
- **Colours**: the median of a patch, from a photo of a real watch when possible.
- **Product renders** often draw a light halo around small marks (dots, arrows). Measure them
  with the colour mask at half intensity, not a loose brightness mask, or they come out too large.
- **Small or blurry things** (icons, thin print): zoom in (`NEAREST`, 4–8×) with a tick every
  2–5 pt, and read the shape before drawing it. The signal mark is a filled "D" with arcs, not
  bars; the GW-B5600's mark next to SNZ is a mute speaker, not Bluetooth.

## 5. Write the model and its face

In `Sources/CasioClockWidget/Models/<Name>/`:

- **`Casio<Name>.swift`**: an `enum` conforming to `CasioModel`, with:
  - `kind`, which is permanent because it identifies placed widgets;
  - `displayName`, `summary`, `canvas` and `widgetArea` (the square the widget shows);
  - `caseBackground`, the palette, `lcd` (its `LCDStyle`) and `face(_:)`;
  - a `#Preview`.

  The header comment names the reference and the mapping.
- **`<Name>Face.swift`**: the face.
  - Case shapes: `CutCornerRect`, `BrickPattern` or your own `Shape`s, traced with profiles.
  - Every printed label as `InkText(text:font:).placed(in: measuredBox, color:)`; vertical labels
    use `placed(vertical:angle:)`. Never size print with `Text` and a font size: font metrics
    drift by points (the A158W's and GMW-B5000's labels did).
  - Weight: compare a stem (the I of CASIO) on photo and render; the photo's is about 0.5 pt
    wider from blur. Heavy print takes `bold` with a smaller `barBold`: thickened equally all
    round, Michroma's S closes into an 8 ("CA8IO").
  - A middle dot "·" in an InkText string is drawn as a round dot a third of the cap height with
    space on both sides, as the watches print it (the fonts' own are small and tight).
  - When the stand-in font's glyph differs from the watch's, split the string and place the
    pieces. Michroma's slash drops below the baseline, so the W-800H's 12/24H is three boxes.
  - The window: an `LCDPanel` with `frame`, the measured `glass` and the module display. Draw the
    window so it doesn't cover nearby print. On the W-800H a too-wide surround hid half of
    12/24H.

If the face is wider than tall, a `caseExtension` makes the case taller to fill the widget. Draw
everything in the reference's coordinates and move each group into its `CaseExtension` band
(`.band(.display, of: stretch)`, `stretch.windowGrowth`, …; the rule is in
`Kit/CaseExtension.swift`). `check` renders without the extension (`CASIO_REFERENCE_LAYOUT=1`).

## 6. The display

If the watch's module already has a display (REFERENCES.md, *Casio LCD modules*) and its photo
shows it the same way, use that display: `LCDPanel(display: Module593Display.self, …)`.

Otherwise write `LCD/Module<number>Display.swift` (or `<Name>Display`), an `LCDModuleDisplay`
measured in the reference's canvas coordinates:

- **Glass**: `glass` is the measured window size and `canvasOrigin` where it sits. When you move
  a window later, move both, and the characters stay where they were measured.
- **Runs**: each line of characters is an `LCDRun`, listed in `static let runs` (a test keeps
  every run inside the glass).
  - `glyph` is the measured ink height and `baseline` its bottom.
  - `xScale` sets the glyph width (measure single digits, not whole lines).
  - `tracking` makes the pitch between characters match (`runs` gives both).
  - `colonGap` places the hours relative to the minutes.
  - Live digits get their own timer windows when `tracking` ≠ 0, so the live clock stays exact.
- **Computing a run** instead of iterating. Tracking is applied before the `xScale` squeeze, and
  a DSEG digit advances 0.816 em with about 0.61 em of ink (em = `glyph`):
  - `xScale` = measured ink width ÷ (0.61 × glyph);
  - `tracking` = measured pitch ÷ xScale − 0.816 × glyph;
  - for a trailing run, `edge` = last ink right edge + (right bearing ≈ 0.1 × glyph + tracking) × xScale;
  - `colonGap`: the gap from the hours' last digit to the minutes' first, minus one digit cell and
    the colon cell (0.2 em + tracking), all × xScale.
  An `LCDText` run with wide tracking needs a larger `width`, or SwiftUI truncates it to "…".
- **LCD font**: each face has its own 7-segment font, `LCDFont.casio("<Model>")`, generated
  from `tools/lcd_fonts.json` by `tools/casio_segfont.py` (needs fontTools). The fonts are
  drop-in replacements for DSEG7 Classic (same advances and the same ink box for "8": `box`
  "Bold" upright, "BoldItalic" slanted), so runs measured with DSEG stay valid. Per face:
  - `thickness`, `gap` and `slant` relative to a 2:3 digit box (as fitted on the photo's digits);
  - `corner`: "point" (DSEG-like bar ends) or "miter" (outer bars reach the corners);
  - `seven`: the 7's segments ("abcf" for a 7 with the top-left hook);
  - `one`: `{left, width}` in font units, the 1's ink measured on the photo (many modules draw
    it wider or further left than a plain b+c).
  Measure them on the photo's digits, regenerate, and keep the element boxes including the 1s.
- **Text**:
  - Fixed text uses `LCDText(text:font:run:style:)`; the live time uses `LiveHoursMinutes` and
    `LiveSeconds`.
  - The strings come from `context.displayParts(blankDigit:)`.
  - A DSEG7 font draws S, U, O and N in Casio's 7-segment shapes.
  - Characters in fixed cells, or double-width letters, get a run each. Module 240 draws the W as
    an L and a U in a double cell.
- **Marks**: shared ones are in `LCD/LCDMarks.swift` (`SignalMark(arcs:)`, `BellMark`), the
  rest are shapes in the display, placed in their measured ink boxes.
- **Dot-matrix characters**: `DotMatrixText` with the right glyph set (`.round5x7` for the
  GMW-B5000, `.bold5x7` for the GW-B5600, `.block5x5` for the DBC-32's weekday), the measured
  pitch and dot size, and `slant` for italic.
- **Printed LCD words** use `InkText`.
- **Several windows** (the AE-1200WH's dial, indicators, map and main window): one display per
  window, each an `LCDPanel`; a round window is a square glass with a radius of half its width.
  Shapes that are not characters (a world map, a zone's segments) are traced from the image into
  1 pt rows.
- **Analogue indicators** (LCD hands) can't keep time in a widget that redraws hourly: leave them
  out and say so in `notes`.
- **Two versions of one watch** (the A700W and its negative): one face with a palette and a
  geometry per version (`A700WPalette`, `A700WGeometry`), each measured on its own image mapped
  onto the same canvas; their displays share one layout type (`A700WLayout`).
- **Same module, different photo**: if the module looks different through another watch's window
  (narrower digits, other spacing), give that watch its own measured layout.
  `Module593Layout` is shared by `Module593Display` (F-91W) and `A158WDisplay`.

Check the live path too: render with `CASIO_LIVE=1` and compare it with the static render.

**Keep the timeline small.** WidgetKit refuses a timeline archive over about 10 MB ("too large
timeline archive" in the simulator's log, and the widget stays a placeholder). Every separate view
adds to it: draw repeated marks (dial ticks, numerals, grid dots) as one `Shape`, not a `ForEach`
of views. The AE-1200WH's 60 ticks and 12 numerals as views made 10.5 MB; as two shapes, 5 MB.

## 7. Register

In `CasioCatalogue.swift`, add the model to `CasioModels.all` and
`CasioWatchWidget<Casio<Name>>()` to `CasioWidgets.homeScreen`. Nothing else is needed (a
`CatalogueTests` failure means one of the two is missing).

## 8. Check against the reference

```bash
python3 tools/casio_measure.py check references/<Name>.json --out ref-dir
```

The command:

1. maps the archived image onto the canvas;
2. renders the face at the manifest's time and time zone, without the case extension;
3. compares every element;
4. writes `side.png`, plus `flagged.png` (photo over render) for every element off by more than
   1.5 pt.

It exits 1 until nothing is off. Options:

- `--images DIR` reads the images from somewhere other than the NAS archive;
- `--lit` renders the light;
- `CASIO_SCRATCH` sets the Swift build folder.

For every flag, look at `flagged.png` and decide which kind it is:

| What you see | Cause | Fix |
|---|---|---|
| a box edge equals the element box's edge | the box catches a neighbour (arrow, case line, frame line, LCD shadow) | tighten the box |
| the photo's print is dim, the render's bright | the photo is dark, or the face's colour comes from a real photo | a photo mask and `renderMask` |
| a label is narrower, wider or shifted | the label was sized by font metrics | `InkText` in the measured box |
| a whole LCD line is off | `xScale`, `tracking`, `colonGap` or the anchor | measure the digits one by one (`runs`) and fix the run |
| one digit is off, the rest match | the face's font (see below) | fix `one` / `seven` in `tools/lcd_fonts.json` and regenerate |
| an icon is a different size or shape | drawn from a guess | zoom in, redraw it, place it in its ink box |
| an indicator is missing | a state the render doesn't have (DST, PM) | `timeZone` / `twelveHour` in the manifest |
| part of a label is missing | another layer covers it (a window surround) | fix the window or the drawing order |

The ink-box check can miss a label that another layer partly covers (its box still spans the
visible ends): look at `side.png` too. The W-800H's ADJUST lost its last 2.5 pt under the window.

Never loosen the tolerance and never drop an element to make the check pass. Leave something out
only for a documented limitation, and say why in `notes`.

**Font limitations**: live digits come from WidgetKit's timer text, so a glyph can't be swapped
in the view; change the face's font instead. One "1" per font: where a module draws the 1 in
different places in different lines, the hours' 1 is measured and the others are noted.

## 9. Review and ship

- Look at `side.png` as a whole: case outline, window, frame, colours, and anything the elements
  don't cover. Add an element for anything you fix this way, so the check keeps it fixed.
- Run `swift test` in this folder (`ManifestTests` and `RenderTests` included); `just format-check`
  and `just lint` cover the package.
- When you change shared code (`LCD/`, `Kit/`), the repository's `.improve/` golden renders show
  which other faces moved.
- Build the app, add the widget on the simulator and tap it for the light.
- Add the model to the README's list and its reference to REFERENCES.md. A new font goes into
  `Resources/` with its licence (OFL) and its name into `CaseFont`.
