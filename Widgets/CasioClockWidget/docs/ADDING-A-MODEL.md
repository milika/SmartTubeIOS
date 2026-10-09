# Adding a model

How each watch in this package was made, step by step. The goal is a face as close as possible to
the real watch: every printed label within about 1 pt of the reference image and every display
character within about 1.5 pt, colours sampled from a photo, no element invented.

Tools: `tools/casio_measure.py` (Python 3 with Pillow, NumPy and SciPy) and the opt-in render test
`ReferenceRenderTests`. Keep reference images, canvases and renders outside the repository (for
example `~/DevTemp/smarttube/scratch/ref-<model>/`).

## 1. Find a reference image

A straight, front-on, sharp image of the real watch, the larger the better; see
[REFERENCES.md](REFERENCES.md#finding-new-references) for where to look and the licence rules.
Archive it in the NAS folder and add its row to REFERENCES.md.

## 2. Map it onto a canvas

Pick the canvas: an origin in image pixels and a size in points, so the watch's face (and any
print on the case you want to keep) fits. One image pixel per point is fine; use `--scale` for
very large or small images, `--rotate` to level a tilted photo.

```bash
python3 tools/casio_measure.py canvas ref.png 540 580 860 700 --out ref-dir
```

`grid.png` shows a 10 pt grid over the image; read rough positions from it. Record the mapping in
the model's header comment and in REFERENCES.md.

## 3. Measure

Measure ink boxes on `photo-canvas.png` with a small spec file of the elements (name, colour mask,
a box that contains just that element):

```json
[{"name": "CASIO", "mask": "white", "box": [360, 140, 505, 175]},
 {"name": "HHMM",  "mask": "dark",  "box": [275, 380, 530, 478]}]
```

```bash
python3 tools/casio_measure.py boxes ref-dir/photo-canvas.png spec.json
```

Also sample colours (median of a patch; take colours from a real photo if the reference is a
product render), and trace lines and corners with brightness profiles across the face.

## 4. Write the model

In `Sources/CasioClockWidget/Models/<Name>/`:

- `Casio<Name>.swift`: an `enum` conforming to `CasioModel` — `kind` (permanent: it identifies
  placed widgets), `displayName`, `summary`, `canvas`, `widgetArea` (the square the widget
  shows), `caseBackground`, the palette, `lcd` (its `LCDStyle`), `face(_:)`, and a `#Preview`
  (copy one from an existing model). The header comment names the reference and the mapping.
- `<Name>Face.swift`: the face — case shapes (`CutCornerRect`, `BrickPattern`, own `Shape`s),
  printed labels as `InkText(...).placed(in: measuredBox, color:)` (vertical ones with
  `placed(vertical:angle:)`), then an `LCDWindow` with the module's display placed in the glass.

If the face is wider than tall, a `caseExtension` makes the case taller so the widget is filled
(see the F-91W); elements keep their measured size, the LCD window grows by half and the groups
below move down.

## 5. The display

If the watch uses a module that already has a display (REFERENCES.md, *Casio LCD modules*),
place that display: `Module593Display.placed(in: glass, context:, style:)`. Otherwise write
`LCD/Module<number>Display.swift` (or `<Name>Display` without a number), an `LCDModuleDisplay`
measured in the reference's canvas coordinates with a `canvasOrigin` at its glass:

- strings from `context.displayParts(blankDigit:)`, `DisplayParts.weekday3`,
  `DisplayParts.twoCells`, `DisplayParts.sevenSegmentLetters` (7-segment weekday letters);
- fixed characters with `LCDText`, live ones with `LiveHoursMinutes` and `LiveSeconds`;
- marks from `LCD/LCDMarks.swift` or new shapes; printed LCD words with `InkText`.

Calibrate the characters with digit runs on the reference and on a render (step 7):

```bash
python3 tools/casio_measure.py runs ref-dir/photo-canvas.png 275 400 620 476
```

DSEG's glyph height is exact; width comes from `xScale`; when the real digits sit closer or
further apart than DSEG's cells, set `tracking` (and `colonGap`) on `LiveHoursMinutes` /
`LiveSeconds` — each live digit then gets its own timer window, so the live clock stays exact.
Check the live path too: render with `CASIO_LIVE=1` and compare it with the static render.

## 6. Register

In `CasioCatalogue.swift`: add the model to `CasioModels.all` and
`CasioWatchWidget<Casio<Name>>()` to `CasioWidgets.homeScreen`. Nothing else: the app's widget
extension lists the catalogue. (A `CatalogueTests` failure means one of the two is missing.)

## 7. Compare with the reference

Render the face on its whole canvas and compare:

```bash
CASIO_RENDER=Casio<Name> CASIO_OUT=ref-dir/render.png CASIO_TIME=2024-06-30T22:58:50 CASIO_12H=1 \
    swift test --filter referenceRender
python3 tools/casio_measure.py boxes ref-dir/photo-canvas.png spec.json ref-dir/render.png
python3 tools/casio_measure.py side ref-dir/photo-canvas.png ref-dir/render.png --out side.png
```

Set the time to the one shown in the reference image. Fix anything flagged `<<` (over 1.5 pt) and
look at `side.png`. `CASIO_LIT=1` renders the light.

## 8. Check and ship

- `swift test` in this folder; `just format-check` and `just lint` cover the package.
- Build the app, add the widget on the simulator, tap it for the light.
- Add the model to the README's list; its reference to REFERENCES.md; a new font goes into
  `Resources/` with its licence and its name into `CaseFont` (the font test checks the bundled files
  are exactly the fonts in use).
