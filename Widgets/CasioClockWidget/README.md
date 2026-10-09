# CasioClockWidget (experimental)

Home Screen widgets that are live digital clocks drawn as real Casio watches, one widget per
watch, as close to the real watch as we can measure: every face is laid out from a front-on
reference image, the time runs live to the second, and tapping a widget turns on its light. One
model also has an Apple Watch complication.

A self-contained Swift package (iOS 17, macOS 14, watchOS 10) with no dependencies on the app; its
only resources are free fonts.

## The watches

| Watch | Model type | Display | Light | Notes |
|---|---|---|---|---|
| Casio F-91W | `CasioF91W` | module 593 | bright mint | also an Apple Watch complication |
| Casio A158W | `CasioA158W` | module 593 (measured on its own photo) | bright mint | chrome case |
| Casio A168W | `CasioA168W` | module 3298 | blue-green EL | colours from a photo of a real watch |
| Casio W-59 | `CasioW59` | module 590 | bright mint | |
| Casio W-800H | `CasioW800H` | W-800H display (year, SNZ/ALM/SIG) | bright mint | navy (W-800H-2AV) |
| Casio W-738H | `CasioW738H` | W-738H display | segments glow | inverted (negative) display |
| Casio CA-53W | `CasioCA53W` | module 3208 | bright mint | calculator watch; the real one has no light |
| Casio W-86 | `CasioW86` | W-86 display | ice-blue EL | |
| G-Shock DW-5000C | `CasioDW5000C` | module 240 | warm bulb | the first G-Shock (1983) |
| G-Shock DW-5600E | `CasioDW5600E` | module 3229 | blue-green EL | the widget leaves the PROTECTION / G-SHOCK bezel out |
| G-Shock GW-B5600 | `CasioGWB5600` | GW-B5600 display | white LED | Midnight Green (GW-B5600MG), face only; the camouflage is a stand-in |
| G-Shock GMW-B5000 | `CasioGMWB5000` | module 3459 | white-blue LED | the widget leaves the steel bezel out |

Every face is checked against its reference image: each printed label, mark, display character
and the LCD window within 1.5 pt (`tools/casio_measure.py check`, see
[docs/ADDING-A-MODEL.md](docs/ADDING-A-MODEL.md)). Known differences from the real watches:

- DSEG's segment shapes stand in for Casio's. Some modules draw a "1" wider or further left, and
  module 593's "7" has a shorter top bar. These are listed in each model's manifest notes.
- Icons such as the signal and alarm marks are always shown, as in the reference images.
- The faces' fonts are free look-alikes, stretched to the measured ink boxes.

## Use it

1. Add this folder as a local package (Xcode: File > Add Package Dependencies… > Add Local…) and
   link the `CasioClockWidget` library to your **widget extension**.
2. List the catalogue in the extension's `WidgetBundle`; every watch appears, and new ones need no
   change here:

   ```swift
   import CasioClockWidget

   @main
   struct MyWidgets: WidgetBundle {
       var body: some Widget {
           CasioWidgets.homeScreen
       }
   }
   ```

Each widget is a small (`systemSmall`) Home Screen widget, named after its watch in the widget
gallery. Tap it for the light (iOS 17 interactive widgets). 12- or 24-hour time follows the device.

### Apple Watch

Apps can't make watch faces; models with a complication provide a rectangular one for Apple's
faces (Modular, Modular Duo, Infograph Modular) and the Smart Stack: the LCD with day, date, time
and live seconds — the model's glass on full-colour faces, the face's tint on tinted ones; no
light. List them in a watchOS widget extension inside a watch app, and show
`CasioComplicationGallery()` on the watch app's screen:

```swift
@main
struct CasioComplications: WidgetBundle {
    var body: some Widget {
        CasioWidgets.complications
    }
}
```

In SmartTube: `SmartTubeApp/DownloadWidget` (the widget extension's bundle),
`SmartTubeApp/Watch` (watch app) and `SmartTubeApp/WatchComplications` (watch extension).

### Remove

Delete the `CasioWidgets…` lines and the package dependency.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layout of the package, faces and canvases, the
  LCD module displays, how the time stays live, the light, the catalogue, tests.
- [docs/ADDING-A-MODEL.md](docs/ADDING-A-MODEL.md) — the method for adding a watch: reference,
  manifest, measuring, the face and display, the check to 0 elements off, review and shipping; a
  table of what each kind of difference means.
- [docs/REFERENCES.md](docs/REFERENCES.md) — every reference image (source, licence, canvas
  mapping, archive location), the typefaces and their stand-ins, the Casio LCD modules.
- `references/<Model>.json` — each model's reference manifest; `python3 tools/casio_measure.py
  check references/<Model>.json` compares the face with its archived reference image.

## Fonts

All under the SIL Open Font License 1.1, licences in `Sources/CasioClockWidget/Resources/`:
DSEG7 / DSEG14 Classic by Keshikan for the LCD; Michroma, Archivo Expanded Black, Saira Medium
and Saira Expanded SemiBold (Google Fonts) as look-alikes of the watches' printing. Details in
[docs/REFERENCES.md](docs/REFERENCES.md#typefaces).

## Tests

`swift test` in this folder (see [ARCHITECTURE.md](docs/ARCHITECTURE.md#tests)). The repository's
`just format-check` and `just lint` cover the package.
