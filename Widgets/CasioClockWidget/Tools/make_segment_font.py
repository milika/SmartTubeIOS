#!/usr/bin/env python3
"""Builds F91WSegment.ttf, the LCD font of the Casio clock widget.

The widget's seconds must be WidgetKit timer text (the only thing a widget can redraw
every second), so the LCD digits have to come from a font for the seconds to match the
hours and minutes. This draws a small segment font from scratch — digits, colon, and the
letters of the weekday abbreviations (SU MO TU WE TH FR SA) — in the style of the F-91W's
LCD: slightly slanted bars with pointed ends.

Requires fontTools (dev only):  pip install fonttools
Run from the package folder:    python3 Tools/make_segment_font.py
"""
import math
import os

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "F91WSegment"
UPM = 1000
CAP = 700  # glyph height
W = 430  # digit body width
ADVANCE = 500  # digit advance (monospaced)
COLON_ADVANCE = 240
T = 64  # segment thickness
GAP = 14  # gap between segments
SLANT = math.tan(math.radians(5))  # the LCD's lean


def skew(p):
    x, y = p
    return (round(x + y * SLANT), round(y))


def bar(p0, p1, t=T):
    """A segment from p0 to p1 with pointed ends, as a polygon."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy * t / 2, ux * t / 2
    tip = t / 2
    a = (x0 + ux * tip, y0 + uy * tip)
    b = (x1 - ux * tip, y1 - uy * tip)
    return [(x0, y0), (a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (x1, y1),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


L, R = 30 + T / 2, 30 + W - T / 2  # vertical bar centres
B, M, TOP = T / 2, CAP / 2, CAP - T / 2  # horizontal bar centres
CX = (L + R) / 2

SEGMENTS = {
    "a": ((L + GAP, TOP), (R - GAP, TOP)),
    "b": ((R, TOP - GAP), (R, M + GAP)),
    "c": ((R, M - GAP), (R, B + GAP)),
    "d": ((L + GAP, B), (R - GAP, B)),
    "e": ((L, M - GAP), (L, B + GAP)),
    "f": ((L, TOP - GAP), (L, M + GAP)),
    "g": ((L + GAP, M), (R - GAP, M)),
    # 14-segment extras for letters
    "g1": ((L + GAP, M), (CX - GAP / 2, M)),
    "g2": ((CX + GAP / 2, M), (R - GAP, M)),
    "i": ((CX, TOP - GAP), (CX, M + GAP)),
    "l": ((CX, M - GAP), (CX, B + GAP)),
    "h": ((L + T * 0.7, TOP - T * 0.7), (CX - T * 0.45, M + T * 0.55)),
    "j": ((R - T * 0.7, TOP - T * 0.7), (CX + T * 0.45, M + T * 0.55)),
    "k": ((L + T * 0.7, B + T * 0.7), (CX - T * 0.45, M - T * 0.55)),
    "m": ((R - T * 0.7, B + T * 0.7), (CX + T * 0.45, M - T * 0.55)),
}

DIGITS = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}

LETTERS = {
    "A": ["a", "b", "c", "e", "f", "g1", "g2"],
    "E": ["a", "d", "e", "f", "g1"],
    "F": ["a", "e", "f", "g1"],
    "H": ["b", "c", "e", "f", "g1", "g2"],
    "M": ["b", "c", "e", "f", "h", "j"],
    "O": ["a", "b", "c", "d", "e", "f"],
    "R": ["a", "b", "e", "f", "g1", "g2", "m"],
    "S": ["a", "f", "g1", "g2", "c", "d"],
    "T": ["a", "i", "l"],
    "U": ["b", "c", "d", "e", "f"],
    "W": ["b", "c", "e", "f", "k", "m"],
}


def draw(pen, polygons):
    for poly in polygons:
        pts = [skew(p) for p in poly]
        pen.moveTo(pts[0])
        for p in pts[1:]:
            pen.lineTo(p)
        pen.closePath()


def glyph(polygons):
    pen = TTGlyphPen(None)
    draw(pen, polygons)
    return pen.glyph()


def segments_glyph(names):
    return glyph([bar(*SEGMENTS[n]) for n in names])


def colon_glyph():
    d = T * 1.05
    cx = COLON_ADVANCE / 2
    dots = []
    for cy in (CAP * 0.27, CAP * 0.70):
        dots.append([(cx - d / 2, cy - d / 2), (cx + d / 2, cy - d / 2),
                     (cx + d / 2, cy + d / 2), (cx - d / 2, cy + d / 2)])
    return glyph(dots)


def empty_glyph():
    return TTGlyphPen(None).glyph()


def main():
    order = [".notdef", "space", "figurespace", "colon"]
    glyphs = {".notdef": empty_glyph(), "space": empty_glyph(),
              "figurespace": empty_glyph(), "colon": colon_glyph()}
    metrics = {".notdef": (ADVANCE, 0), "space": (ADVANCE, 0),
               "figurespace": (ADVANCE, 0), "colon": (COLON_ADVANCE, 0)}
    cmap = {0x20: "space", 0x2007: "figurespace", ord(":"): "colon"}

    for ch, segs in DIGITS.items():
        name = f"digit{ch}"
        order.append(name)
        glyphs[name] = segments_glyph(list(segs))
        metrics[name] = (ADVANCE, 0)
        cmap[ord(ch)] = name
    for ch, segs in LETTERS.items():
        order.append(ch)
        glyphs[ch] = segments_glyph(segs)
        metrics[ch] = (ADVANCE, 0)
        cmap[ord(ch)] = ch

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": FAMILY, "styleName": "Regular",
                       "uniqueFontIdentifier": f"{FAMILY}-Regular",
                       "fullName": f"{FAMILY} Regular", "psName": f"{FAMILY}-Regular",
                       "version": "Version 1.0", "copyright": "Drawn for SmartTube's Casio clock widget."})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200,
                sCapHeight=CAP, sxHeight=CAP)
    fb.setupPost()
    out = os.path.join(os.path.dirname(__file__), "..", "Sources", "CasioClockWidget", "Resources",
                       f"{FAMILY}.ttf")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fb.save(out)
    print("wrote", os.path.normpath(out))


if __name__ == "__main__":
    main()
