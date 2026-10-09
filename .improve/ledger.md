# Improvement ledger (run 2)

- Started: 2026-10-09 · Branch: improve/2026-10-09-casio2 · Worktree: ~/DevTemp/smarttube/wt/improve-casio2
- BASE: 0aeeee8f · Args: run, scope `Widgets/CasioClockWidget` ("on clocks module only"), budget 10
- Status: finished (5 commits incl. this record; I-00..I-04 done)
- Run 1 (BASE 4c77a950, 8 commits) is in git history: `git show a58523c2:.improve/ledger.md`.

## Project rules (condensed)
- Conventional Commits with task ID (`refactor(casio): … (#357)`), trailer `Co-Authored-By: Claude Opus 5.5`.
- Never hand-edit project.pbxproj; never define ENABLE_DOWNLOADS; leave Localizable.xcstrings (owner's uncommitted work - hence the worktree).
- Temp/build output under ~/DevTemp/smarttube/<kind>; no push / upload unless asked.
- One definition per constant/identifier; Swift Testing; `just format-check` / `just lint` cover the package.

## Baseline (BASE 0aeeee8f)
| Gate | Command | Exit | Result |
|---|---|---|---|
| build macOS (-warnings-as-errors) | `.improve/verify.sh` | 0 | 0 warnings |
| test | `swift test` (package) | 0 | 27 passed, 0 failing, 1 opt-in skipped (referenceRender) |
| build iOS / watchOS Simulator | xcodebuild, package scheme | 0 / 0 | 0 warnings |
| swift-format / swiftlint (package) | repo configs | 0 / 0 | 0 / 0 findings |
| golden renders | `.improve/golden.sh` + `goldcmp.py` | 0 | 300 images (now all 12 models, was 4); two runs identical (max diff 0) |

## System map (delta since run 1)
12 models (Models/<Name>/: model + face); 10 module displays (LCD/, LCDModuleDisplay, canvas-measured); LiveClock/ (hourly entries + timer, TimerDigit windows for tracked digits); catalogue; Kit (FaceCanvas, InkText, shapes); docs/ (ARCHITECTURE, ADDING-A-MODEL, REFERENCES); tools/casio_measure.py; opt-in ReferenceRenderTests.

## Hotspots (top, 12 months)
| score | churn | cx | path |
|---|---|---|---|
| 79.3 | 10 | 508 | Models/GMWB5000/GMWB5000Face.swift |
| 69.2 | 9 | 493 | Models/DW5000C/DW5000CFace.swift |
| 33.4 | 5 | 428 | Models/F91W/F91WFace.swift |
| 13.5 | 2 | 434 | Models/DW5600E/DW5600EFace.swift |

## Backlog
| ID | Kind | Location | Problem | Evidence | Move | Risk | Effort | Conf | Status | Commit |
|---|---|---|---|---|---|---|---|---|---|---|
| I-00 | safety-net | .improve/GoldenRenderTests.swift | goldens covered 4 of 12 models | 108 → 300 images | iterate CasioModels.all | low | S | 95 | done | (tooling, committed with ledger) |
| I-01 | structural | W800HFace `Arrow`, DW5600EFace `Arrow` | duplicate of Kit `Pointer` (byte-identical path) | diff of the three bodies | delete, use Pointer | low | S | 95 | done | 693e8cbd |
| I-02 | structural | 7 displays call `DisplayParts.sevenSegmentLetters` | one decision (DSEG7 can't draw Casio's S/U/O/N) at 7 call sites; a new DSEG7 display that forgets it shows "bu" | grep: 7 sites | LCDText applies it whenever its font is DSEG7 | low | S | 90 | done | c664f004 |
| I-03 | structural | GMWB5000Face/DW5000CFace `Shield`, DW5600EFace/GWB5600Face `Badge` | the SHOCK RESIST shield polygon written 4 times | 4 private shapes, same 7-point path | Kit `ShockResistShield(cornerCut:shoulder:)` | low | S | 90 | done | 3d5ed560 |
| I-04 | structural | 10 displays end with `.lcdSegmentShadow(style).offset(-canvasOrigin).frame(glass)` | the "measured on the face canvas, shown in its glass" rule copied 10 times | grep: 10 offsets, 11 shadows | `LCDModuleDisplay.canvasOrigin` + `inGlass { }` helper | low | M | 85 | done | dcb576c0 |

## Rulings
- Ruling: new ledger for run 2 instead of resuming run 1 - run 1 finished; its ledger stays in history - none.
- Ruling: golden harness extended (I-00) before any edit - the 8 new faces had no pixel gate - none.

## Looks bad, is fine
- Split dates (month, separator, day) in W738H / W800H / DW5600E / GWB5600 displays - each separator has its own measured size and position; a helper would take every number as a parameter.
- `ShockResistBadge` views in GMWB5000Face / DW5000CFace - different badge artwork around the now-shared shield shape.
- `UNUSED? Model.kind/displayName/...` from a naive grep - protocol requirements read generically (CasioWatchWidget<Model>), not dead.
- Identity calibration constants (`tracking = 0`, `scale = 1`) in displays - measured knobs kept explicit so recalibration edits one number.
- One-off shapes (Camouflage, Slanted, Banner, Slant, SunMark, BluetoothMark, BatteryMark ×2 - different marks) - each draws one watch's print.
- Two down-triangles (DW5000C badge, CA-53W labels) - generic geometry, not one decision; wait for a third.
- Face files' size and the `extra / 4`, `3 * extra / 4` offsets - per-watch layout (run 1 ruling stands).

## Log
- I-00 golden harness: 4 → 12 models (300 images), deterministic (two runs, max diff 0).
- I-01 693e8cbd: Arrow ×2 → Kit Pointer; goldens 0.
- I-02 c664f004: LCDText maps DSEG7 letters; 7 call sites removed; new test red→green; goldens 0.
- I-03 3d5ed560: ShockResistShield in Kit; 4 private shapes removed; goldens 0.
- I-04 dcb576c0: LCDModuleDisplay.canvasOrigin + inGlass; 11 displays; goldens 0.
