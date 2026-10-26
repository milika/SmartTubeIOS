---
status: accepted
date: 2026-10-23
deciders: fork maintainer
---
# 0010. Offer the native iOS player as an explicit opt-in

## Context and problem statement

The default YouTube IFrame player is reliable but iOS suspends its inline `WKWebView` in the
background. The existing Background Playback setting therefore has no effect on regular videos.
Upstream issues #106, #114, #163, and #165 request background playback or a native-player choice.
Issue #174 documents that native stream resolution can be slow or fall back to low quality;
the fork includes PR #175's VisionOS-first mitigation.

## Decision

Keep the YouTube player as the default and offer Native Player as a persisted iOS preference.
Route newly opened videos through the selected engine; never hand off an active video between
engines. Disable Background Playback for the YouTube player and explain that it requires Native
Player. Preserve the saved background preference while it is unavailable.

## Consequences
- Good: users can explicitly trade stream reliability for background audio, PiP, and native controls.
- Good: the UI no longer implies that background playback works with the YouTube player.
- Bad: native playback still depends on unofficial clients that can regress despite the #175 mitigation.
- Bad: two iOS playback paths remain user-visible and require regression coverage.

## Alternatives considered

- Silently switch engines when backgrounding: rejected because it recreates ADR-0007's risky handoff.
- Keep the ineffective toggle enabled: rejected because it misrepresents supported behavior.
