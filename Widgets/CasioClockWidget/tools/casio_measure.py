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

Masks: white (light, unsaturated print), dark (LCD ink), light (anything bright), gold, red, blue.
"""

import argparse
import json
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage


def masks(path, size):
    a = np.asarray(Image.open(path).convert("RGB").resize(size)).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum, sat = a.mean(2), a.max(2) - a.min(2)
    return {
        "white": (lum > 165) & (sat < 50),
        "dark": lum < 80,
        "light": lum > 120,
        "gold": (r > 120) & (r - b > 40),
        "red": (r > 100) & (r - g > 45) & (r - b > 30),
        "blue": (b > 110) & (b - r > 40),
    }


def ink_box(mask, box, min_fraction=0.05):
    x0, y0, x1, y1 = box
    sub = mask[2 * y0:2 * y1, 2 * x0:2 * x1]
    if sub.sum() < 6:
        return None
    labels, n = ndimage.label(sub)
    sizes = ndimage.sum(sub, labels, range(1, n + 1))
    keep = np.isin(labels, [i + 1 for i, s in enumerate(sizes) if s >= max(6, min_fraction * max(sizes))])
    ys, xs = np.nonzero(keep)
    return (x0 + xs.min() / 2, y0 + ys.min() / 2, x0 + (xs.max() + 1) / 2, y0 + (ys.max() + 1) / 2)


def cmd_canvas(args):
    photo = Image.open(args.image).convert("RGB")
    if args.rotate:
        photo = photo.rotate(args.rotate, resample=Image.BICUBIC, fillcolor=(255, 255, 255))
    s, ox, oy = args.scale, args.ox, args.oy
    canvas = photo.transform(
        (2 * args.w, 2 * args.h), Image.EXTENT, (ox, oy, ox + args.w * s, oy + args.h * s), Image.BICUBIC)
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


def cmd_boxes(args):
    size = Image.open(args.canvas).size
    photo = masks(args.canvas, size)
    render = masks(args.render, size) if args.render else None
    for item in json.load(open(args.spec)):
        a = ink_box(photo[item["mask"]], item["box"])
        if render is None:
            print(f"{item['name']:16} " + (f"{a[0]:6.1f} {a[1]:6.1f} {a[2]:6.1f} {a[3]:6.1f}  "
                                            f"w {a[2] - a[0]:5.1f} h {a[3] - a[1]:5.1f}" if a else "none"))
            continue
        b = ink_box(render[item["mask"]], item["box"])
        if a is None or b is None:
            print(f"{item['name']:16} missing (photo {a}, render {b})")
            continue
        d = [b[i] - a[i] for i in range(4)]
        flag = "  <<" if max(abs(v) for v in d) > 1.5 else ""
        print(f"{item['name']:16} Δ {d[0]:+5.1f} {d[1]:+5.1f} {d[2]:+5.1f} {d[3]:+5.1f}{flag}")


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
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    sys.exit(main())
