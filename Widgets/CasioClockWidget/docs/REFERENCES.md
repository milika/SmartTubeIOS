# References

Every face is drawn on a canvas measured from one front-on reference image of the real watch.
The images are **used for measuring only** — none is shipped in the app or committed to this
repository. Copies of all of them are archived on the owner's NAS:

    /Volumes/main/tempMac/smarttube/casio-references/

(file names start with the model, then the source). The Wikimedia Commons originals can be
downloaded again from the links below; the product images were supplied by the owner.

## Reference images

The **canvas** column says how canvas points map onto the image. Each model's manifest,
`references/<Model>.json`, records the same mapping with the image's archive file name, the time
it shows and the measured elements, so `tools/casio_measure.py check references/<Model>.json`
compares the face with its reference again in one step (see [ADDING-A-MODEL.md](ADDING-A-MODEL.md)).

| Model | Image | Source and licence | Canvas |
|---|---|---|---|
| F-91W | `Casio_F-91W_5051.jpg` (1920 px version) | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Casio_F-91W_5051.jpg), Ashley Pomeroy, CC BY-SA 3.0 | image px = (370.1, 818.5) + 1.951 × canvas; 594 × 530 pt before the case extension |
| A158W | `A158W.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:A158W.jpg), Casiolink, CC BY-SA 4.0 | canvas = (image − (110, 175)) × 1.5 |
| G-Shock GMW-B5000 | `Wikipedia-Casio-G-Shock-Edelstahl-800.jpg` (GMW-B5000D-1ER) | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Wikipedia-Casio-G-Shock-Edelstahl-800.jpg), Minzoblate, CC BY-SA 4.0 | canvas = image − (85, 160) |
| G-Shock DW-5000C | `DW-5000.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:DW-5000.jpg), Stollenbaeck, CC BY-SA 4.0 | canvas = image scaled to 960 px − (170, 240) |
| W-59 | `Casio W-59 digital watch.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Casio_W-59_digital_watch.jpg), Ricce, public domain | canvas = (image − 120) / 2 |
| CA-53W | `Casio CA-53W, 1.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Casio_CA-53W,_1.jpg), Morn, CC BY-SA 4.0 | levelled by 0.8°, canvas = image scaled to 960 px − (160, 290) |
| W-86 | `Casio W-86 digital watch (front closeup minor retouch).jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Casio_W-86_digital_watch_(front_closeup_minor_retouch).jpg), Multicherry, CC BY-SA 4.0 (light colour from the same author's backlight photo) | image px = (435, 390) + 1.5 × canvas, before the case extension |
| A168W | Casio A168WA-1W product image (1000 px), from bomar.rs | supplied by the owner; Casio's image, measured only | canvas = image − (230, 250) |
| A168W (colours) | photo of a real A168WA-1 (1100 px) | supplied by the owner; colours only (the product render's are off) | — |
| W-738H | product image, front (1200 px) | supplied by the owner; measured only | canvas = image − (280, 180) |
| W-800H | W-800H-2AV (navy) product image (1000 px) | supplied by the owner; measured only (three more W-800H images archived for comparison) | canvas = image − (180, 160) |
| G-Shock GW-B5600 | GW-B5600MG-1 (Midnight Green) product image (1200 px) | supplied by the owner; measured only | canvas = image − (270, 420), before the case extension |
| LA680W | LA680WA-1 product image (1200 px) | supplied by the owner (2026-10-09); measured only | image px = (360, 300) + 0.75 × canvas, before the case extension |
| G-Shock DW-5600E | DW-5600E-1V product image (2000 px, TACEQ) | supplied by the owner; measured only (an angled Amazon image archived for colours) | canvas = image − (540, 580), before the case extension |

How well each face matches its image: every element in its manifest (`references/<Model>.json`)
and the LCD window are within 1.5 pt (`tools/casio_measure.py check`, 2026-10-10). Where a font
limitation makes one character differ, the manifest leaves that character out and says why in
its `notes`. Product-image bezels the widgets leave out (G-Shocks) are not in the manifests.

### Queued (references collected, not built yet)

All supplied by the owner (2026-10-09), product images, for measuring only; archived in the NAS
folder with "(queued)" in the name.

| Watch | Image | Notes |
|---|---|---|
| A178W | A178WA-1A, 1000 px | chrome; SUN 6-30, P, SNZ / ALM / SIG row; blue WR, DUAL TIME / 10 YEAR BATTERY |
| A700W | A700WE-1A, 1000 px | slim chrome; coloured ALARM / SIG / SPL / CHRONO labels above the LCD |
| A700W (negative) | A700W with negative display, cyan print, mesh band, 1100 px | inverted LCD (`litInk`, as the W-738H) |
| F-105W | F-105W-1A, 1000 px | black resin, blue face, ILLUMINATOR band, EL BACKLIGHT/RESET |

## Typefaces

The watches' printing uses commercial typefaces; free look-alikes stand in (all SIL Open Font
License 1.1, licences in `Sources/CasioClockWidget/Resources/`):

| On the watch | Stand-in | Notes |
|---|---|---|
| Microgramma / Eurostile Extended (CASIO logo, most labels) | Michroma (Google Fonts) | subset |
| Neue Helvetica Extended Black ("F-91W", WATER RESIST, ILLUMINATOR, …) | Archivo Expanded Black | static instance of Archivo's variable font, wght 900 / wdth 125 |
| Eurostile Medium (ALARM CHRONOGRAPH, small print) | Saira Medium | static instance |
| the wide "WR" mark | Saira Expanded SemiBold | wght 600 / wdth 125, stretched |
| LCD segments | DSEG7 / DSEG14 Classic Bold Italic, DSEG7 Classic Bold (upright) | by Keshikan, [keshikan.net](https://www.keshikan.net/fonts-e.html) |

The F-91W's typefaces were identified with Fonts In Use:
[fontsinuse.com/uses/74290](https://fontsinuse.com/uses/74290).

## Casio LCD modules

Casio builds one numbered LCD module into several watches; each module's display is drawn once
(`LCD/`) and placed in each watch's glass. The module numbers are the commonly cited ones for
these watches; they were not checked against Casio's manuals or case backs. Where no number was
at hand, the display is named after the watch.

| Display | Module | Watches here | Other watches with it |
|---|---|---|---|
| `Module593Display` | 593 | F-91W | A168W uses 3298 (below), not 593 |
| `A158WDisplay` | 593 | A158W | the same module measured on the A158W photo (narrower digits) |
| `Module3459Display` | 3459 | GMW-B5000 | GW-B5600 family shows the same layout |
| `Module240Display` | 240 | DW-5000C | — |
| `Module590Display` | 590 | W-59 | — |
| `Module3208Display` | 3208 | CA-53W | — |
| `Module3298Display` | 3298 | A168W | — |
| `Module3229Display` | 3229 | DW-5600E | — |
| `W738HDisplay` | not checked | W-738H | — |
| `W800HDisplay` | not checked | W-800H | — |
| `GWB5600Display` | not checked | GW-B5600 | — |
| `W86Display` | not checked | W-86 | — |
| `LA680WDisplay` | not checked | LA680W | — |

## Finding new references

- Wikimedia Commons first (free licences, often front-on): search the model name in the File
  namespace. Check the licence on the file page.
- Otherwise a retailer's or Casio's product image, supplied by the owner and used for measuring
  only. Prefer a straight, front-on, high-resolution shot; a second, real photo helps with colours
  (product renders are often off).
- Archive the image in the NAS folder above and add a row to the table.
