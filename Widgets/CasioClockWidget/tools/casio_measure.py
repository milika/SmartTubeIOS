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
      side.png. Exits 1 if an element is missing or off by more than 1.5 pt.

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
from PIL import Image, ImageDraw
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


def ink_box(mask, box, min_fraction=0.05):
    x0, y0, x1, y1 = box
    sub = mask[2 * y0:2 * y1, 2 * x0:2 * x1]
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
    photo = Image.open(image).convert("RGB")
    if rotate:
        photo = photo.rotate(rotate, resample=Image.BICUBIC, fillcolor=(255, 255, 255))
    return photo.transform((2 * w, 2 * h), Image.EXTENT, (ox, oy, ox + w * scale, oy + h * scale), Image.BICUBIC)


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
    bad = 0
    for item in elements:
        a = ink_box(photo[item["mask"]], item["box"])
        if rendered is None:
            print(f"{item['name']:16} " + (f"{a[0]:6.1f} {a[1]:6.1f} {a[2]:6.1f} {a[3]:6.1f}  "
                                            f"w {a[2] - a[0]:5.1f} h {a[3] - a[1]:5.1f}" if a else "none"))
            continue
        b = ink_box(rendered[item["mask"]], item["box"])
        if a is None or b is None:
            print(f"{item['name']:16} missing (photo {a}, render {b})")
            bad += 1
            continue
        d = [b[i] - a[i] for i in range(4)]
        off = max(abs(v) for v in d) > 1.5
        bad += off
        print(f"{item['name']:16} Δ {d[0]:+5.1f} {d[1]:+5.1f} {d[2]:+5.1f} {d[3]:+5.1f}{'  <<' if off else ''}")
    return bad


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
               CASIO_REFERENCE_LAYOUT="1")
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
    bad = compare(canvas, manifest["elements"], render_path, manifest.get("masks"))
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
