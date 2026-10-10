#!/usr/bin/env python3
"""Measure a Casio face on its reference image and compare it with a render.

The workflow is in docs/ADDING-A-MODEL.md. Needs Python 3 with Pillow, NumPy and SciPy
(`pip install pillow numpy scipy`). All coordinates are canvas points; images are handled at 2 px
per point, like the renders from ReferenceRenderTests.

  canvas IMAGE OX OY W H [--scale S] [--rotate DEG] [--out DIR]
      Map the reference image onto a W x H point canvas whose (0, 0) is image pixel (OX, OY), with
      S image pixels per point (default 1). --rotate levels a tilted photo first. Writes
      photo-canvas.png and grid.png (10 pt grid, labelled every 50).
  boxes CANVAS SPEC.json [RENDER]
      Ink box of every element in SPEC (a list of {"name", "mask", "box": [x0, y0, x1, y1]}), on the
      photo canvas and, with RENDER, the difference; differences over 1.5 pt are flagged.
  runs IMAGE X0 Y0 X1 Y1 [--light]
      Horizontal runs of ink (dark by default) in a box: one run per LCD digit, for calibrating a
      display's glyph squeeze and tracking.
  side CANVAS RENDER [--out side.png]
      Photo canvas and render side by side, half size.
  check MANIFEST [--images DIR] [--out DIR] [--lit]
      Compare a model with its reference in one go, from its manifest (references/<Model>.json):
      maps the archived image onto the canvas, renders the face at the reference's time without
      the case extension (ReferenceRenderTests), compares every element's ink box and writes
      side.png (and flagged.png: photo over render of every flagged element). Exits 1 if an element
      is missing or off by more than 1.5 pt. An element's "renderMask" names a different mask for
      the render, where the face's colour differs from the image on purpose; "kind": "edges"
      measures a window's four edges (the LCD glass) instead of an ink box.

Masks: white (light, unsaturated print), dark (LCD ink), light (anything bright), gold, red, blue.
A manifest can define its own as thresholds, for example {"white": {"lum": [150, null],
"|r-b|": [null, 50]}}: each key (r, g, b, lum, sat, differences such as "r-b", absolute ones such
as "|r-b|") must lie between its [min, max] (null: open).
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from scipy import ndimage


PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARCHIVE = "/Volumes/main/tempMac/smarttube/casio-references"


def masks(path, size, spec=None):
    a = np.asarray(Image.open(path).convert("RGB").resize(size)).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum, sat = a.mean(2), a.max(2) - a.min(2)
    defaults = {
        "white": (lum > 165) & (sat < 50),
        "dark": lum < 80,
        "light": lum > 120,
        "gold": (r > 120) & (r - b > 40),
        "red": (r > 100) & (r - g > 45) & (r - b > 30),
        "blue": (b > 110) & (b - r > 40),
    }
    if not spec:
        return defaults
    channels = {"r": r, "g": g, "b": b, "lum": lum, "sat": sat}

    def value(key):
        if key.startswith("|"):
            return np.abs(value(key.strip("|")))
        if "-" in key:
            x, y = key.split("-")
            return channels[x] - channels[y]
        return channels[key]

    custom = {}
    for name, limits in spec.items():
        m = np.ones(lum.shape, dtype=bool)
        for key, (lo, hi) in limits.items():
            v = value(key)
            if lo is not None:
                m &= v > lo
            if hi is not None:
                m &= v < hi
        custom[name] = m
    return {**defaults, **custom}


def pixel(v):
    """A canvas point (whole or half) as an index into the 2 px per point images."""
    return int(round(2 * v))


def ink_box(mask, box, min_fraction=0.05):
    x0, y0, x1, y1 = box
    sub = mask[pixel(y0):pixel(y1), pixel(x0):pixel(x1)]
    if sub.sum() < 6:
        return None
    labels, n = ndimage.label(sub)
    sizes = ndimage.sum(sub, labels, range(1, n + 1))
    keep = np.isin(labels, [i + 1 for i, s in enumerate(sizes) if s >= max(6, min_fraction * max(sizes))])
    if not keep.any():
        return None
    ys, xs = np.nonzero(keep)
    return (x0 + xs.min() / 2, y0 + ys.min() / 2, x0 + (xs.max() + 1) / 2, y0 + (ys.max() + 1) / 2)


def photo_canvas(image, ox, oy, w, h, scale=1, rotate=0):
    # Phone photos are often stored on their side with an EXIF orientation tag.
    photo = ImageOps.exif_transpose(Image.open(image)).convert("RGB")
    if rotate:
        photo = photo.rotate(rotate, resample=Image.BICUBIC, fillcolor=(255, 255, 255))
    return photo.transform((2 * w, 2 * h), Image.EXTENT, (ox, oy, ox + w * scale, oy + h * scale), Image.BICUBIC)


def window_edges(mask, box):
    """Edges of a bright window (an LCD glass) in a box: the first column / row, scanning in from
    each side through a band across the middle, where most of the band is inside the mask. Dark
    characters inside the window don't matter."""
    x0, y0, x1, y1 = box
    sub = mask[pixel(y0):pixel(y1), pixel(x0):pixel(x1)]
    h, w = sub.shape
    rows = solid(sub[int(h * 0.4):int(h * 0.6)].mean(0) > 0.6)
    cols = solid(sub[:, int(w * 0.4):int(w * 0.6)].mean(1) > 0.6)
    if not rows.any() or not cols.any():
        return None
    xs, ys = np.nonzero(rows)[0], np.nonzero(cols)[0]
    return (x0 + xs[0] / 2, y0 + ys[0] / 2, x0 + (xs[-1] + 1) / 2, y0 + (ys[-1] + 1) / 2)


def solid(line, length=6):
    """`line` with runs shorter than `length` samples (3 pt) cleared: an outline's anti-aliased
    edge next to the window is not the window."""
    out = np.zeros_like(line)
    start = None
    for i, value in enumerate(list(line) + [False]):
        if value and start is None:
            start = i
        elif not value and start is not None:
            if i - start >= length:
                out[start:i] = True
            start = None
    return out


def measure(mask, item):
    return window_edges(mask, item["box"]) if item.get("kind") == "edges" else ink_box(mask, item["box"])


def cmd_canvas(args):
    canvas = photo_canvas(args.image, args.ox, args.oy, args.w, args.h, args.scale, args.rotate)
    canvas.save(f"{args.out}/photo-canvas.png")
    grid = canvas.copy()
    draw = ImageDraw.Draw(grid)
    for x in range(0, args.w, 10):
        draw.line([(2 * x, 0), (2 * x, 2 * args.h)], fill=(255, 0, 255) if x % 50 == 0 else (90, 0, 90))
    for y in range(0, args.h, 10):
        draw.line([(0, 2 * y), (2 * args.w, 2 * y)], fill=(0, 255, 255) if y % 50 == 0 else (0, 90, 90))
    for x in range(0, args.w, 50):
        draw.text((2 * x + 2, 2), str(x), fill=(255, 255, 0))
    for y in range(0, args.h, 50):
        draw.text((2, 2 * y + 2), str(y), fill=(255, 255, 0))
    grid.save(f"{args.out}/grid.png")
    print(f"wrote {args.out}/photo-canvas.png and grid.png ({args.w} x {args.h} pt)")


def compare(canvas, elements, render=None, mask_spec=None):
    """Prints each element's ink box (or, with a render, its difference); returns the number of
    elements missing or off by more than 1.5 pt."""
    size = Image.open(canvas).size
    photo = masks(canvas, size, mask_spec)
    rendered = masks(render, size, mask_spec) if render else None
    bad, flagged = 0, []
    for item in elements:
        a = measure(photo[item["mask"]], item)
        if rendered is None:
            print(f"{item['name']:16} " + (f"{a[0]:6.1f} {a[1]:6.1f} {a[2]:6.1f} {a[3]:6.1f}  "
                                            f"w {a[2] - a[0]:5.1f} h {a[3] - a[1]:5.1f}" if a else "none"))
            continue
        b = measure(rendered[item.get("renderMask", item["mask"])], item)
        if a is None or b is None:
            print(f"{item['name']:16} missing (photo {a}, render {b})")
            bad += 1
            flagged.append(item)
            continue
        d = [b[i] - a[i] for i in range(4)]
        off = max(abs(v) for v in d) > 1.5
        bad += off
        if off:
            flagged.append(item)
        print(f"{item['name']:16} Δ {d[0]:+5.1f} {d[1]:+5.1f} {d[2]:+5.1f} {d[3]:+5.1f}{'  <<' if off else ''}")
    compare.flagged = flagged
    return bad


def zoom_sheet(canvas, render, items, path, margin=12):
    """Photo (top) and render (bottom) of each item's box with a margin, side by side."""
    photo, rendered = Image.open(canvas).convert("RGB"), Image.open(render).convert("RGB").resize(
        Image.open(canvas).size)
    tiles = []
    for item in items:
        x0, y0, x1, y1 = item["box"]
        crop = (2 * (x0 - margin), 2 * (y0 - margin), 2 * (x1 + margin), 2 * (y1 + margin))
        a, b = photo.crop(crop), rendered.crop(crop)
        tile = Image.new("RGB", (a.width, 2 * a.height + 18), (255, 255, 255))
        ImageDraw.Draw(tile).text((2, 2), item["name"], fill=(255, 0, 0))
        tile.paste(a, (0, 18))
        tile.paste(b, (0, 18 + a.height))
        draw = ImageDraw.Draw(tile)
        for top in (18, 18 + a.height):
            draw.rectangle((2 * margin, top + 2 * margin, a.width - 2 * margin, top + a.height - 2 * margin),
                           outline=(255, 0, 255))
        tiles.append(tile)
    if not tiles:
        return
    width = sum(t.width for t in tiles) + 6 * len(tiles)
    sheet = Image.new("RGB", (width, max(t.height for t in tiles)), (255, 255, 255))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 6
    sheet.save(path)


def cmd_boxes(args):
    compare(args.canvas, json.load(open(args.spec)), args.render)


def cmd_runs(args):
    image = Image.open(args.image)
    m = masks(args.image, image.size)["light" if args.light else "dark"]
    sub = m[2 * args.y0:2 * args.y1, 2 * args.x0:2 * args.x1]
    cols = np.nonzero(sub.sum(0) > 3)[0] / 2 + args.x0
    if len(cols) == 0:
        print("no ink")
        return
    runs, start, prev = [], cols[0], cols[0]
    for c in cols[1:]:
        if c - prev > 2:
            runs.append((start, prev + 0.5))
            start = c
        prev = c
    runs.append((start, prev + 0.5))
    print("  ".join(f"{a:.1f}-{b:.1f} (w {b - a:.1f})" for a, b in runs))


def cmd_side(args):
    photo = Image.open(args.canvas).convert("RGB")
    render = Image.open(args.render).convert("RGB").resize(photo.size)
    sheet = Image.new("RGB", (photo.width * 2 + 10, photo.height), (255, 0, 255))
    sheet.paste(photo, (0, 0))
    sheet.paste(render, (photo.width + 10, 0))
    sheet.resize((sheet.width // 2, sheet.height // 2)).save(args.out)
    print(f"wrote {args.out}")


def cmd_check(args):
    manifest = json.load(open(args.manifest))
    model, c = manifest["model"], manifest["canvas"]
    w, h = c["size"]
    out = args.out or tempfile.mkdtemp(prefix=f"casio-{model}-")
    os.makedirs(out, exist_ok=True)
    canvas = os.path.join(out, "photo-canvas.png")
    photo_canvas(os.path.join(args.images, manifest["image"]), *c["origin"], w, h, c.get("scale", 1),
                 c.get("rotate", 0)).save(canvas)
    full = os.path.join(out, "render-full.png")
    env = dict(os.environ, CASIO_RENDER=model, CASIO_OUT=full, CASIO_TIME=manifest["time"],
               CASIO_12H="1" if manifest.get("twelveHour") else "0", CASIO_LIT="1" if args.lit else "0",
               CASIO_REFERENCE_LAYOUT="1", CASIO_TZ=manifest.get("timeZone", "GMT"))
    command = ["swift", "test", "--filter", "referenceRender"]
    if os.environ.get("CASIO_SCRATCH"):
        command += ["--scratch-path", os.environ["CASIO_SCRATCH"]]
    result = subprocess.run(command, cwd=PACKAGE, env=env, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(full):
        sys.exit(f"reference render failed:\n{result.stdout[-2000:]}{result.stderr[-2000:]}")
    # The render covers the model's canvas; cut the reference's canvas out of it.
    dx, dy = manifest.get("renderOffset", [0, 0])
    render = Image.new("RGB", (2 * w, 2 * h), (128, 128, 128))
    render.paste(Image.open(full).convert("RGB"), (-2 * dx, -2 * dy))
    render_path = os.path.join(out, "render.png")
    render.save(render_path)
    print(f"{model} at {manifest['time']} ({out})")
    for note in manifest.get("notes", []):
        print(f"note: {note}")
    bad = compare(canvas, manifest["elements"], render_path, manifest.get("masks"))
    if compare.flagged:
        zoom_sheet(canvas, render_path, compare.flagged, os.path.join(out, "flagged.png"))
    args.canvas, args.render, args.out = canvas, render_path, os.path.join(out, "side.png")
    cmd_side(args)
    print(f"{len(manifest['elements'])} elements, {bad} missing or off by more than 1.5 pt")
    return 1 if bad else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("canvas")
    p.add_argument("image")
    for name in ("ox", "oy"):
        p.add_argument(name, type=float)
    for name in ("w", "h"):
        p.add_argument(name, type=int)
    p.add_argument("--scale", type=float, default=1)
    p.add_argument("--rotate", type=float, default=0)
    p.add_argument("--out", default=".")
    p.set_defaults(run=cmd_canvas)
    p = sub.add_parser("boxes")
    p.add_argument("canvas")
    p.add_argument("spec")
    p.add_argument("render", nargs="?")
    p.set_defaults(run=cmd_boxes)
    p = sub.add_parser("runs")
    p.add_argument("image")
    for name in ("x0", "y0", "x1", "y1"):
        p.add_argument(name, type=int)
    p.add_argument("--light", action="store_true")
    p.set_defaults(run=cmd_runs)
    p = sub.add_parser("side")
    p.add_argument("canvas")
    p.add_argument("render")
    p.add_argument("--out", default="side.png")
    p.set_defaults(run=cmd_side)
    p = sub.add_parser("check")
    p.add_argument("manifest")
    p.add_argument("--images", default=ARCHIVE)
    p.add_argument("--out")
    p.add_argument("--lit", action="store_true")
    p.set_defaults(run=cmd_check)
    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
