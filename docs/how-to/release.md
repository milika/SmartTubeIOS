> status: current (2026-09-11), partial — see "Not yet documented" below

# How to cut a release

**When to use:** bumping the version and preparing a changelog entry before shipping a build.

## What's actually automated today

1. Bump the version in `SmartTubeApp/Config/Base.xcconfig` — `MARKETING_VERSION` (user-facing,
   e.g. `5.6`) and `CURRENT_PROJECT_VERSION` (build number, monotonic integer). That file is
   the only place these live (`just identity-check` fails if they reappear in
   `project.pbxproj`). For a one-off build number, `scripts/testflight_upload.sh <build>`
   passes it on the `xcodebuild` command line instead of editing any file.
2. `just changelog` regenerates the `Unreleased` section of `CHANGELOG.md` from Conventional
   Commits since the last tag (`cliff.toml`, WS1-T1.7). Review and edit before committing — it's a
   draft, not a final copy-paste.
3. `just ci` — must pass before tagging.

## Not yet documented

Signing, archiving (`xcodebuild archive`), and TestFlight/App Store Connect upload steps are
currently done by hand and have no written runbook anywhere in either repo (checked: no
`archive`/`TestFlight`/`App Store Connect` process doc exists). Whoever runs a release should
write down the actual steps here the next time they do one, rather than this doc guessing at a
generic Apple process that might not match how this project actually ships.
