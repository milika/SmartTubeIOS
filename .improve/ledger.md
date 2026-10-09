# Improvement ledger

- Started: 2026-10-09 · Branch: improve/2026-10-09 · Worktree: ~/DevTemp/smarttube/wt/improve-casio
- BASE: 4c77a950 · Args: run, scope `Widgets/CasioClockWidget` ("only on watch module"), no focus, budget 10
- Status: finished (8 commits, I-01..I-07 done)

## Project rules (condensed, SmartTube AGENTS.md / CLAUDE.md + owner's global rules)
- Conventional Commits with task ID: `refactor(casio): … (#357)`; trailer `Co-Authored-By: Claude Opus 5.5`.
- Swift 6 concurrency style; one definition per constant/identifier; Swift Testing for unit tests.
- Never hand-edit project.pbxproj. Never define ENABLE_DOWNLOADS. Leave Localizable.xcstrings alone (owner's uncommitted work - why this is a worktree).
- Temp/build output only under ~/DevTemp/smarttube/<kind>; worktrees under ~/DevTemp/smarttube/wt/.
- New fonts must be free (OFL) with license in Resources/ + README.
- No push / upload unless the owner asks.

## Baseline (BASE 4c77a950)
| Gate | Command | Exit | Pass | Fail | Skip | Warnings | Time |
|---|---|---|---|---|---|---|---|
| build (macOS) | `swift build --scratch-path …/casio-improve` (+ `-warnings-as-errors`) | 0 | | | | 0 | 9.6s |
| test | `swift test --scratch-path …/casio-improve` | 0 | 19 | 0 | 0 | | <1s run |
| build iOS | `xcodebuild -scheme CasioClockWidget -destination generic/platform=iOS Simulator` | 0 | | | | 0 | 9s |
| build watchOS | same, `generic/platform=watchOS Simulator` | 0 | | | | 0 | 8s |
| swift-format | `xcrun swift-format lint --strict --recursive --configuration .swift-format <pkg>/Sources <pkg>/Tests` | 1 | | | | 20 | |
| swiftlint | `swiftlint lint --config .improve/swiftlint-casio.yml` (repo config, `included:` = package) | 2 | | | | 73 | |
| golden renders | `.improve/golden.sh <tag>` + `.improve/goldcmp.py base <tag> 3` | 0 | 108 imgs | | | | 2s |

Failing tests (keys): none (Swift Testing output; gate.py doesn't parse it - keyed by hand from `✘ Test "…"` lines; baseline set is empty).
Diagnostics (keys): `.improve/baseline-diags.txt` (swift-format + swiftlint, 93 lines / 63 keys).
Pre-existing: 20 swift-format + 73 swiftlint findings in the package; the package is outside the project's `just format`/`just lint` paths, so nothing enforces them today.
Golden gate: 4 models × 3 dates (UTC Fri 19:46:24; Berlin DST Sun 03:05:07; UTC New Year 00:00:00) × 12/24 h × lit/unlit, as face (canvas) and widget tile (170 pt), plus the F-91W complication full-colour and accented. Two runs of identical code differ by ≤ 3/255 per channel (blur AA), so tolerance = 3.

## System map
Purpose: Home Screen widgets (and one watch complication) drawing live Casio watches. SwiftPM package, iOS 17 / macOS 14 / watchOS 10; consumed by SmartTubeApp's widget extension (DownloadLiveActivity.swift WidgetBundle) and SmartTubeWatchComplications.
Layers (dependencies point down):
- Models/<Name>/ - one enum per watch (CasioModel: kind, canvas, widgetArea, fonts, palette, LCDStyle) + its Face view + public Widget wrapper. F91W also a complication.
- Widget/ - generic CasioWatchWidget<Model> (iOS), CasioComplicationWidget<Model> (watchOS), CasioClockProvider (hourly timeline + lit entries), CasioBacklightIntent (per-model defaults key).
- LCD/ - LCDStyle/LCDShadow, LCDFont (DSEG metrics), LCDText, LCDWindow, DisplayParts (time/date strings), LiveClock (timer start, LiveHoursMinutes), LiveSeconds, Module593Display (shared F-91W/A158W layout), DotMatrixText.
- Kit/ - FaceCanvas (+ place modifiers), CaseFont, BundledFonts, Shapes (CutCornerRect, Pointer, BrickPattern), TextEffects, InkText.
Entry points: public `Casio<Model>Widget`, `CasioF91WComplication`, `CasioF91WComplicationPreview`, `CasioBacklightIntent`.
State: only UserDefaults key per model (light-until); everything else is pure drawing from CasioFaceContext.
Tests: Swift Testing - DisplayParts strings, timeline entries, model registry (kinds, fonts, widget area), dot-matrix glyphs, date texts. No render tests in the repo (golden gate lives in .improve/).
Doc drift: CasioWatchWidget.swift header still describes one entry per minute + seconds timer from the minute start (now hourly entries + LiveClock "10:MM:SS" timer); Package.swift says "today CasioF91WWidget"; Pointer doc says "red triangles beside LIGHT, MODE and 24HR" (now white ones on G-Shocks too).

## Hotspots (top at start, 12 months)
| score | churn | complexity | path |
|---|---|---|---|
| 66.7 | 4 | 693 | Models/GMWB5000/GMWB5000Face.swift |
| 31.2 | 3 | 432 | Models/F91W/F91WFace.swift |
| 28.8 | 2 | 598 | Models/DW5000C/DW5000CFace.swift |
| 22.6 | 3 | 313 | Models/A158W/A158WFace.swift |
| 15.3 | 6 | 106 | Tests/ModelTests.swift |
| 13.7 | 4 | 142 | LCD/Module593Display.swift |
Coupling: CasioModel.swift ↔ ModelTests.swift 0.83 (registering a model touches both - expected).

## Backlog
| ID | Kind | Location | Problem (lens term) | Evidence | Move | Risk | Effort | Conf | Status | Commit |
|---|---|---|---|---|---|---|---|---|---|---|
| I-01 | docs | Widget/CasioWatchWidget.swift:8-13, Package.swift:4-5, Kit/Shapes.swift Pointer | comments contradict the code (unknown unknowns) | timeline is hourly since f7652e85; 3 models use white Pointers | rewrite comments | low | S | 95 | done | c31b2f7e |
| I-02 | structural | Models/F91W/F91WFace.swift:7-11 | dead pass-through properties | `date`,`calendar`,`uses12HourClock`,`previewSeconds` each appear once (their declaration) | delete | low | S | 95 | done | 6527582c |
| I-03 | structural | 5 × `DisplayParts.make(for: context.date, calendar: context.calendar, twelveHour: context.uses12HourClock, blankDigit:)` | repeated knowledge: how a face context maps to display strings | 5 call sites, 3 lines each | add `CasioFaceContext.displayParts(blankDigit:)` | low | S | 90 | done | 8d810526 |
| I-04 | structural | LCD/LiveSeconds.swift + 4 call sites | inconsistent interface: LiveSeconds takes date/calendar/previewSeconds, its sibling LiveHoursMinutes takes the context | 4 call sites pass the 3 context fields | take `context` | low | S | 90 | done | 74f6df9d |
| I-05 | structural | DisplayParts.swift:36, GMWB5000Face.swift:229, DW5000CFace.swift:175 | one decision (LCD right-aligns a 1-2 digit number in two cells with a blank) in 3 copies | grep `< 10 ?` | `DisplayParts.twoCells(_:blank:)` | low | S | 85 | done | 2f501897 |
| I-06 | structural | 9 per-model `michroma/saira/…` helpers + 40 literal PostScript names | information leak: font names spelled in ~40 places; a typo silently falls back to the system font (fonts test only checks each model's hand-kept list) | grep: Michroma-Regular ×17, Saira-Medium ×9, ArchivoExpanded-Black ×5 … | names once in CaseFont; helpers once in a CasioModel extension; model `fonts` lists built from the names and the model's LCDStyle | low | M | 85 | done | b73e1238, 859c4f86 (README) |

| I-07 | safety-net | Tests/RenderTests.swift (new) | no test renders a face: a blank face or a dead light passes `swift test` | 0 render tests at BASE | characterization: every CasioModels.all model renders ink; lit ≠ unlit | low | S | 90 | done | a12b6e7b |

Status values: todo · doing · done · parked (reason) · deferred (needs owner) · rejected

## Rulings
- Ruling: worktree at ~/DevTemp/smarttube/wt/improve-casio, not ../SmartTube-improve - owner's global rule names the folder; the main tree has the owner's uncommitted Localizable.xcstrings - none.
- Ruling: golden renders are the behaviour gate, kept in .improve/ (committed with the ledger at the end), not a committed snapshot test - the repo has no snapshot infrastructure and PNG goldens are OS/renderer-version brittle - a future run has to regenerate them at its BASE.
- Ruling: pixel tolerance 3/255 - identical code renders differ by up to 3 (blur anti-aliasing) - a 1-3 level real change would pass unseen.
- Ruling: swiftlint/swift-format run on the package as diagnostics gates (no new findings in touched files) though the project's `just` gates don't cover the package - they're the project's own tools and configs - none.
- Ruling: kept `F91W.digitSqueeze` (an alias of Module593Display.digitSqueeze) - a second name, not a second definition; the complication reads naturally with it - none.
- Ruling: CasioModel extension gives every model `michroma/saira/sairaExpanded/archivoBlack(_:)`, also models that don't use some fonts - one place instead of nine copies; an unused static func costs nothing - none.
- Ruling: commit the golden harness (GoldenRenderTests.swift, golden.sh, goldcmp.py, verify.sh, swiftlint-casio.yml) with the ledger, not its logs or PNGs - next run can regenerate goldens at its BASE - none.
- Ruling: not reformatting the package (20 swift-format findings) - outside the project's format gate; a mass reformat is churn the owner didn't ask for - see deferred D-1.

## Deferred (owner decides)
- D-1 Add `Widgets/CasioClockWidget/{Sources,Tests}` to `just format`, `format-check` and `.swiftlint.yml` `included:` (then one `just format` commit). Today 20 format + 73 lint findings accumulate unchecked.

## Findings (not fixed)
- PROC-1 .improve/verify.sh first piped the diags/golden gates through `tail`, hiding their exit codes; it printed ALL GATES GREEN over a RED lint gate during I-04 (caught by reading the output, fixed before that commit). Every committed item was re-run with the fixed script.
- DOC-1 docs drift fixed in I-01 (CasioWatchWidget header, Package.swift, Pointer).

## Looks bad, is fine
- LCD/LCDStyle.swift `unlitOpacity`, LCDFont `allSegments/allLit`, unlit layers in LCDText/LiveHoursMinutes/LiveSeconds - zero users, but a27a050c says "the option stays in LCDStyle for other models" (the owner's queue has more models). Don't re-suggest unless the owner drops it.
- Models/*Face.swift size (GMWB5000Face 250 loc, highest complexity) - each is one watch's measured drawing; splitting moves complexity, doesn't remove it.
- Case-extension arithmetic (`e/4`, `e/2`, `e`) repeated in every face - each model distributes its extra height differently (measured choices), so a shared helper would need per-model parameters for every group.
- Two private `ShockResistBadge`/`Shield` types (GMWB5000Face, DW5000CFace) - different badge designs, only the name is shared.
- `emboldened` draws 9 copies of a view - needed for print bolder than the single-weight stand-in fonts; archive sizes are fine since hourly entries (f7652e85).
- InkText rebuilds glyph outlines in every `path(in:)` - a few short labels per hourly entry; caching would add state for no measurable gain.
- ModelTests has one near-identical test per model - tests are not edited in this run.

## Log
- I-01 done c31b2f7e: comments only; tests 19/0; diags 93 -> 93; goldens ≤3.
- I-02 done 6527582c: 4 dead properties; tests 19/0; goldens ≤3.
- I-03 done 8d810526: context.displayParts, 5 sites; tests 19/0; goldens ≤3.
- I-04 done 74f6df9d: LiveSeconds(context:), 4 sites; first try added a 121-col line (lint RED, fixed); verify.sh exit handling fixed (PROC-1).
- I-05 done 2f501897: DisplayParts.twoCells, 3 copies -> 1; first try named the parameter `n` (lint RED, renamed); lint 73 -> 71.
- I-06 done b73e1238 + 859c4f86: font names 40 literals -> 4 (CaseFont); 9 helpers -> 4 in one extension; README step updated.
- I-07 done a12b6e7b: RenderTests; proven red with the light disabled; tests 19 -> 20.
