# Codebase improvement report: SmartTube · Widgets/CasioClockWidget (2026-10-09)

**Branch:** improve/2026-10-09 (worktree `~/DevTemp/smarttube/wt/improve-casio`) · **BASE:** 4c77a950 · **Commits:** 9 (8 + this report) · **Mode:** run, scope = the Casio watch package

## Summary
The package (4 watch models, ~1,900 source lines) is in good shape: clear layers (Models → Widget / LCD → Kit), small files, pure drawing from one context type. The friction was small-scale duplication of *decisions* that new models copy: font names typed as string literals ~40 times (a typo silently falls back to the system font), the context → display-strings mapping written 5 times, the two-digit date rule 3 times, and two sibling live-time views with different interfaces. Those are now single definitions, stale comments that described the old per-minute timeline are fixed, and a committed render test catches a model that draws nothing or whose light does nothing. Every face, widget and complication renders identically to BASE (108 golden images). The one decision for you: bring the package under `just format` / `just lint` (D-1).

## Verification (before → after)
| Gate | Before (BASE) | After (HEAD) |
|---|---|---|
| tests pass/fail | 19/0 | 20/0 |
| build macOS (`-warnings-as-errors`) | ok, 0 warnings | ok, 0 warnings |
| build iOS Simulator / watchOS Simulator (xcodebuild, package scheme) | ok / ok, 0 warnings | ok / ok, 0 warnings |
| swift-format findings (package) | 20 | 20 (none new in touched files) |
| swiftlint findings (package, repo config) | 73 | 71 |
| golden renders vs BASE (4 models × 3 dates × 12/24 h × lit/off, face + widget; complication full + accented) | - | 108/108 within 3/255 (identical-code noise is 3) |
| source non-blank lines | 1,886 | 1,878 |
| PostScript font-name literals in Swift | 40 | 4 (CaseFont) |

**Verified on:** macOS 27 (swift test, ImageRenderer goldens), Xcode builds for generic iOS Simulator and watchOS Simulator.
**Not verified:** on-device or simulator Home Screen rendering of this branch (the goldens render the same views with ImageRenderer; WidgetKit adds only the timer animation, which these commits don't touch).

## Changes made
| ID | Commit | What | Why (cost removed) | Evidence |
|---|---|---|---|---|
| I-01 | c31b2f7e | comments: hourly timeline + live timer, Package.swift, Pointer | unknown unknowns: header described per-minute entries removed in f7652e85 | comments only; all gates green |
| I-02 | 6527582c | delete 4 unused F91WFace properties | dead code | each name appeared once (its declaration) |
| I-03 | 8d810526 | `context.displayParts(blankDigit:)` | change amplification: 5 copies of the context → DisplayParts mapping | 5 sites → 1 definition |
| I-04 | 74f6df9d | `LiveSeconds(context:)` like `LiveHoursMinutes` | inconsistent sibling interfaces; 4 call sites unpacked the context | 4 sites shortened |
| I-05 | 2f501897 | `DisplayParts.twoCells(_:blank:)` | one date-cell rule in 3 copies | lint 73 → 71 |
| I-06 | b73e1238, 859c4f86 | font names once in `CaseFont`; size helpers once in a `CasioModel` extension; `fonts` lists use the model's LCDStyle; README step | information leak + silent-fallback bug risk; 9 copied helpers | 40 literals → 4 |
| I-07 | a12b6e7b | `RenderTests`: every model renders ink; lit ≠ off | no render coverage at all | proven red with the light disabled |

## Hotspots before → after (complexity / loc)
| path | before | after |
|---|---|---|
| Models/GMWB5000/GMWB5000Face.swift | 693 / 250 | 680 / 246 |
| Models/DW5000C/DW5000CFace.swift | 598 / 219 | 585 / 215 |
| Models/F91W/F91WFace.swift | 432 / 151 | 427 / 146 |
| LCD/Module593Display.swift | 142 / 58 | 132 / 55 |

## Decisions for you (deferred)
- **D-1 Put the package under the project's format and lint gates.** `just format` / `format-check` list explicit paths and `.swiftlint.yml` `included:` lists four folders; `Widgets/CasioClockWidget` is in neither, so 20 swift-format and 71 swiftlint findings sit unchecked. Proposal: add `{{root}}/Widgets/CasioClockWidget/Sources` and `/Tests` to both just recipes and to `included:`, run `just format` once (one `style(casio)` commit), and baseline or fix the lint findings (52 are short identifiers like `e`, `r`, `p` in drawing code - add them to `identifier_name.excluded` or accept them in `.swiftlint.baseline`). Not done: it changes project-wide gate config and reformats every file. Effort S.

## Bugs and other findings
- No behaviour bugs found.
- PROC-1 (this run's own harness): `.improve/verify.sh` at first hid the lint and golden gates' exit codes behind `tail`; it reported green over a red lint gate during I-04. Caught from the output, fixed before that commit; every committed item ran with the fixed script.

## Rulings I made
- Worktree under `~/DevTemp/smarttube/wt/` (your global rule), because the main checkout has your uncommitted `Localizable.xcstrings`.
- Golden renders as the behaviour gate, kept in `.improve/` (harness committed with this report; PNGs and logs not) - the repo has no snapshot infrastructure and image goldens are renderer-version brittle.
- Pixel tolerance 3/255 - two runs of the same code differ by up to 3 (blur anti-aliasing).
- swift-format and swiftlint run on the package as extra gates (no new findings in touched files), though `just` doesn't cover it.
- No mass reformat (see D-1). `F91W.digitSqueeze` alias kept. Every model gets all four font helpers from one extension.

## Looks bad, is fine
- Unlit-segment option (`LCDStyle.unlitOpacity`, `LCDFont.allLit`) has no user - kept on purpose in a27a050c ("the option stays in LCDStyle for other models").
- Big face files (GMWB5000Face 246 loc) - one watch's measured drawing each; splitting moves complexity.
- `e/4`, `e/2`, `e` case-extension arithmetic in every face - each model spreads its extra height differently.
- Two private `ShockResistBadge` types - different badge designs.
- `emboldened` draws 9 copies; `InkText` rebuilds outlines per render - needed for the look; cost is negligible at hourly entries.
- One near-identical "has its own kind" test per model - tests weren't edited.

## Parked
None.

## Suggested next run
After D-1 lands, a `focus: types` run on the faces' layout numbers (measured coordinates as raw literals) is the remaining place where a typo changes the picture silently; the golden harness in `.improve/` is the safety net for it. Worth adding to AGENTS.md: "Casio package: font names only in `CaseFont`; a new model must appear in `CasioModels.all` (RenderTests and ModelTests iterate it)".

## Review / discard
```
git -C ~/DevTemp/smarttube/wt/improve-casio log --oneline 4c77a950..improve/2026-10-09
git -C ~/DevTemp/smarttube/wt/improve-casio diff 4c77a950 --stat
git worktree remove ~/DevTemp/smarttube/wt/improve-casio && git branch -D improve/2026-10-09
```
