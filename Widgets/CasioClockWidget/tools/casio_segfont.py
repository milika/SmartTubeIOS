#!/usr/bin/env python3
"""Generate the package's 7-segment LCD fonts (CasioLCD-<Face>.ttf) from tools/lcd_fonts.json.

Each face's digits are drawn in a font made for it: the segment thickness, the gap between
segments and the slant are measured on the face's reference image (docs/ADDING-A-MODEL.md,
"LCD fonts"). The fonts are drop-in replacements for the DSEG7 Classic variant a face's runs were
measured with: same units per em, advances (digits 816, colon 200), vertical metrics and the
same ink box for "8" (`box`: "Bold" or "BoldItalic"), so the face's runs (squeeze, tracking,
anchors) stay valid and only the segments' shapes change.

The glyphs are designed in a 2:3 box (as the fit measured them: thickness, gap and slant relative
to that box) and then stretched to the DSEG box; the face's squeeze brings them to the photo's
proportions, as in the fit. Needs fontTools (`pip install fonttools`).

    python3 tools/casio_segfont.py            # writes Sources/CasioClockWidget/Resources/CasioLCD-*.ttf
"""

import json
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
RESOURCES = os.path.join(PACKAGE, "Sources", "CasioClockWidget", "Resources")

UPM = 1000
# Glyphs are designed 2 wide by 3 high, the box the fit (tools/lcd_fonts.json) measured them in.
DESIGN_ASPECT = 2 / 3
DIGIT_ADVANCE = 816
COLON_ADVANCE = 200
# The ink box of DSEG7 Classic's "8" (font units), which each font reproduces.
BOXES = {"Bold": (99, 717), "BoldItalic": (62, 754)}

SEGMENTS = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
    "7": "abc", "8": "abcdefg", "9": "abcfgd", "-": "g",
}


def segment_polygons(t, g, s, aspect, corner="point"):
    """The seven segments of an "8" in design coordinates: height 1000 (y down from the top), ink
    width about `aspect` × 1000 including the slant. Bars are `t` × 1000 thick, `g` × 1000 apart,
    leaning `s` (x per y) to the right at the top. `corner` "point": every bar ends in a point (as
    DSEG); "miter": the outer bars are trapezoids reaching the glyph's corners (most Casio
    modules), the middle bar pointed."""
    h = 1000.0
    T, G = t * h, g * h
    W = aspect * h - s * h            # upright width
    mid = h / 2

    def p(x, y):
        return (x + s * (h - y), y)

    def hbar(y0):
        x0, x1 = G + T / 2, W - G - T / 2
        return [p(x0, y0), p(x0 + T / 2, y0 - T / 2), p(x1 - T / 2, y0 - T / 2), p(x1, y0),
                p(x1 - T / 2, y0 + T / 2), p(x0 + T / 2, y0 + T / 2)]

    def vbar(x0, y0, y1):
        a, b = y0 + G + T / 2, y1 - G - T / 2
        return [p(x0 + T / 2, a - T / 2), p(x0 + T, a), p(x0 + T, b), p(x0 + T / 2, b + T / 2),
                p(x0, b), p(x0, a)]

    if corner == "point":
        return {
            "a": hbar(T / 2), "g": hbar(mid), "d": hbar(h - T / 2),
            "f": vbar(0, T / 2, mid), "b": vbar(W - T, T / 2, mid),
            "e": vbar(0, mid, h - T / 2), "c": vbar(W - T, mid, h - T / 2),
        }
    m1, m2 = mid - G / 2, mid + G / 2
    return {
        "a": [p(G, 0), p(W - G, 0), p(W - T - G, T), p(T + G, T)],
        "d": [p(T + G, h - T), p(W - T - G, h - T), p(W - G, h), p(G, h)],
        "f": [p(0, G), p(T, T + G), p(T, m1 - T / 2), p(T / 2, m1), p(0, m1 - T / 2)],
        "e": [p(0, m2 + T / 2), p(T / 2, m2), p(T, m2 + T / 2), p(T, h - T - G), p(0, h - G)],
        "b": [p(W, G), p(W, m1 - T / 2), p(W - T / 2, m1), p(W - T, m1 - T / 2), p(W - T, T + G)],
        "c": [p(W - T, m2 + T / 2), p(W - T / 2, m2), p(W, m2 + T / 2), p(W, h - G), p(W - T, h - T - G)],
        "g": hbar(mid),
    }


def one_bars(one, t, g, s, x_min, left, stretch, corner):
    """The 1 as measured on the reference image: two vertical bars whose ink spans `one["left"]` to
    `left + width` font units (slant included), in the face's corner style."""
    h = 1000.0
    G, T = g * h, t * h
    span = h - 2 * G - T                              # the bars' height without their tips
    width = one["width"] / stretch - s * span         # upright bar width, design units
    x0 = (one["left"] - x_min) / stretch + left       # ink left (the bottom bar's foot)
    mid = h / 2

    def p(x, y):
        return (x + s * (h - y) - s * G, y)

    m1, m2 = mid - G / 2, mid + G / 2
    if corner == "miter":
        upper = [p(x0 + width, G), p(x0 + width, m1 - width / 2), p(x0 + width / 2, m1), p(x0, m1 - width / 2),
                 p(x0, T + G)]
        lower = [p(x0, m2 + width / 2), p(x0 + width / 2, m2), p(x0 + width, m2 + width / 2),
                 p(x0 + width, h - G), p(x0, h - T - G)]
    else:
        def bar(y0, y1):
            a, b = y0 + G + width / 2, y1 - G - width / 2
            return [p(x0 + width / 2, a - width / 2), p(x0 + width, a), p(x0 + width, b),
                    p(x0 + width / 2, b + width / 2), p(x0, b), p(x0, a)]
        upper, lower = bar(T / 2, mid), bar(mid, h - T / 2)
    return [upper, lower]


def build(name, spec):
    t, g, s = spec["thickness"], spec["gap"], spec["slant"]
    aspect = DESIGN_ASPECT
    x_min, x_max = BOXES[spec["box"]]
    segs = segment_polygons(t, g, s, aspect, spec.get("corner", "point"))
    # The "8"'s actual ink (bevels and slant leave it inside the nominal width) maps onto the box.
    ink_x = [x for poly in segs.values() for x, _ in poly]
    left, right = min(ink_x), max(ink_x)
    stretch = (x_max - x_min) / (right - left)          # final width -> DSEG box width

    def to_font(pt):
        x, y = pt
        return (round(x_min + (x - left) * stretch), round(1000 - y))
    glyphs, advances = {".notdef": None}, {".notdef": DIGIT_ADVANCE}
    order = [".notdef", "space", "exclam", "colon", "hyphen", "period"] + [
        "zero one two three four five six seven eight nine".split()[i] for i in range(10)]
    names = dict(zip("0123456789", "zero one two three four five six seven eight nine".split()))
    names["-"] = "hyphen"

    def draw(polys):
        pen = TTGlyphPen(None)
        for poly in polys:
            pts = [to_font(q) for q in poly]
            # Clockwise in font coordinates (y up) for TrueType outer contours.
            area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
            if area > 0:
                pts.reverse()
            pen.moveTo(pts[0])
            for q in pts[1:]:
                pen.lineTo(q)
            pen.closePath()
        return pen.glyph()

    empty = TTGlyphPen(None).glyph()
    glyphs[".notdef"] = empty
    # Per-face glyph details measured on the reference image: the 7's segments ("abcf": with the
    # top-left hook) and the 1 moved right by `oneShift` font units (some modules draw it nearer
    # the next digit).
    segments = dict(SEGMENTS)
    segments["7"] = spec.get("seven", SEGMENTS["7"])
    for ch, glyph_name in names.items():
        polys = [segs[k] for k in segments[ch]]
        if ch == "1" and spec.get("one"):
            polys = one_bars(spec["one"], t, g, s, x_min, left, stretch, spec.get("corner", "point"))
        elif ch == "1" and spec.get("oneShift"):
            shift = spec["oneShift"] / stretch
            polys = [[(x + shift, y) for x, y in poly] for poly in polys]
        glyphs[glyph_name] = draw(polys)
        advances[glyph_name] = DIGIT_ADVANCE
    glyphs["space"] = empty
    glyphs["exclam"] = empty                   # DSEG's digit-wide blank
    advances["space"] = advances["exclam"] = DIGIT_ADVANCE
    # Colon: two square dots at DSEG's heights, centred in its cell (as wide as the face's squeeze
    # allows: at most 140 of the 200 units), leaning with the digits.
    dot = t * 1000
    dot_w = min(dot * stretch, 140)
    pen = TTGlyphPen(None)
    for cy in (286, 686):
        dx = s * (cy - 500) * stretch
        x0 = COLON_ADVANCE / 2 - dot_w / 2 + dx
        pts = [(round(x0), round(cy - dot / 2)), (round(x0 + dot_w), round(cy - dot / 2)),
               (round(x0 + dot_w), round(cy + dot / 2)), (round(x0), round(cy + dot / 2))]
        pts.reverse()
        pen.moveTo(pts[0])
        for q in pts[1:]:
            pen.lineTo(q)
        pen.closePath()
    glyphs["colon"] = pen.glyph()
    advances["colon"] = COLON_ADVANCE
    # Period: one dot on the baseline at the right of a digit cell.
    pen = TTGlyphPen(None)
    pts = [(x_max - round(dot_w), 0), (x_max, 0), (x_max, round(dot)), (x_max - round(dot_w), round(dot))]  # noqa
    pts.reverse()
    pen.moveTo(pts[0])
    for q in pts[1:]:
        pen.lineTo(q)
    pen.closePath()
    glyphs["period"] = pen.glyph()
    advances["period"] = DIGIT_ADVANCE

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    cmap = {ord(" "): "space", ord("!"): "exclam", ord(":"): "colon", ord("-"): "hyphen", ord("."): "period",
            0x2007: "space"}
    cmap.update({ord(c): n for c, n in names.items() if c.isdigit()})
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    metrics = {}
    for glyph_name in order:
        glyph = glyphs[glyph_name]
        glyph.recalcBounds(fb.font["glyf"])
        metrics[glyph_name] = (advances[glyph_name], getattr(glyph, "xMin", 0) or 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=1000, descent=0, lineGap=90)
    family = "CasioLCD " + name
    fb.setupNameTable({
        "familyName": family, "styleName": "Regular", "uniqueFontIdentifier": "CasioLCD-" + name,
        "fullName": family, "psName": "CasioLCD-" + name, "version": "Version 1.0",
        "copyright": "Copyright 2026 SmartTube contributors",
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        "licenseInfoURL": "https://openfontlicense.org",
    })
    fb.setupOS2(sTypoAscender=1000, sTypoDescender=0, sTypoLineGap=90, usWinAscent=1000, usWinDescent=0,
                sCapHeight=1000, sxHeight=500, achVendID="NONE")
    fb.setupPost(italicAngle=0)
    path = os.path.join(RESOURCES, "CasioLCD-%s.ttf" % name)
    fb.save(path)
    return path


def main():
    specs = json.load(open(os.path.join(HERE, "lcd_fonts.json")))
    for name, spec in specs["fonts"].items():
        print("wrote", os.path.relpath(build(name, spec), PACKAGE))


if __name__ == "__main__":
    sys.exit(main())
