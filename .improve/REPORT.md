# Codebase improvement report: SmartTube · Widgets/CasioClockWidget, run 2 (2026-10-09)

**Branch:** improve/2026-10-09-casio2 (worktree `~/DevTemp/smarttube/wt/improve-casio2`) · **BASE:** 0aeeee8f · **Commits:** 5 (4 + this record) · **Mode:** run, scope = the Casio clock package

## Summary
Since run 1 the package grew from 4 to 12 watch models (about 4,200 source lines). The new faces
and displays were each written from a reference image, and a few decisions got copied along the
way: a shape that already existed in the kit, the DSEG7 letter fix-up at seven call sites (easy to
forget on the next display), the G-Shock SHOCK RESIST shield four times, and the "measured on the
face canvas, shown in the glass" step in eleven displays. Each is now defined once. Before any
edit, the golden-render harness was extended from 4 to all 12 models, so every commit was checked
pixel-for-pixel against all faces, lit and unlit, 12/24 h, three dates. Nothing to decide this time.

## Verification (before → after)
| Gate | Before (BASE) | After (HEAD) |
|---|---|---|
| tests pass/fail (1 opt-in skipped) | 27/0 | 28/0 |
| build macOS (`-warnings-as-errors`), iOS / watchOS Simulator | clean | clean |
| swift-format / swiftlint (package) | 0 / 0 | 0 / 0 |
| golden renders vs BASE (12 models × 3 dates × 12/24 h × lit/off, face + widget; complication) | 300, deterministic | 300/300 identical (max diff 0) |
| doc links (`just doc-links`) | ok | ok |
| source non-blank lines | 4,218 | 4,137 |

**Verified on:** macOS (swift test, ImageRenderer goldens); package builds for generic iOS and watchOS Simulator.
**Not verified:** on-device rendering of this branch (the goldens render the same views; the live timer path isn't touched).

## Changes made
| ID | Commit | What | Why (cost removed) | Evidence |
|---|---|---|---|---|
| I-00 | (this record) | golden harness covers all 12 models | the 8 newest faces had no pixel gate | 108 → 300 images |
| I-01 | 693e8cbd | W-800H / DW-5600E use Kit `Pointer` | two private copies of an existing shape | identical paths; goldens 0 |
| I-02 | c664f004 | `LCDText` draws DSEG7 letters in Casio's shapes itself | one decision at 7 call sites; forgetting it shows "bu" for SU | new test red → green; goldens 0 |
| I-03 | 3d5ed560 | Kit `ShockResistShield`; one `shield` constant per face | the same polygon in 4 private shapes, drawn twice per face in 3 faces | goldens 0 |
| I-04 | dcb576c0 | `LCDModuleDisplay.canvasOrigin` + `inGlass(style:)` | one layout rule copied in 11 displays | goldens 0 |

## Hotspots before → after (complexity / loc)
| path | before | after |
|---|---|---|
| Models/GMWB5000/GMWB5000Face.swift | 508 / 195 | 471 / 182 |
| Models/DW5000C/DW5000CFace.swift | 493 / 192 | 460 / 179 |
| Models/DW5600E/DW5600EFace.swift | 434 / 166 | 386 / 136 |
| LCD/Module593Display.swift | 114 / 44 | 110 / 42 |

## Decisions for you (deferred)
None.

## Bugs and other findings
None found.

## Rulings I made
- New ledger for run 2 (run 1's is in history, `git show a58523c2:.improve/ledger.md`).
- Golden harness extended before any edit.
- `ShockResistShield` takes the corner cut as points and/or a fraction of the width, so every face keeps its exact numbers.

## Looks bad, is fine
In `.improve/ledger.md`: protocol members a naive grep calls unused, identity calibration constants, one-off shapes, two generic triangles, split dates, per-face badge views.

## Parked
None.

## Suggested next run
Only when the next few models are in; the remaining duplication is per-watch measurement data, not shared decisions.

## Review / discard
```
git -C ~/DevTemp/smarttube/wt/improve-casio2 log --oneline 0aeeee8f..improve/2026-10-09-casio2
git -C ~/DevTemp/smarttube/wt/improve-casio2 diff 0aeeee8f --stat
git -C ~/SmartTube worktree remove ~/DevTemp/smarttube/wt/improve-casio2 && git -C ~/SmartTube branch -D improve/2026-10-09-casio2
```
