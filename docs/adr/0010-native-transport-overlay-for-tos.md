---
status: accepted
date: 2026-10-18
deciders: maintainer
---
# 0010. Native transport overlay for the TOS player

## Context and problem statement

The TOS player (ADR-0006) renders YouTube's `controls=1` chrome inside its
WKWebView. It is inconsistent with the direct player, cannot show chapter or
SponsorBlock markers on the timeline, and leaves no room for native
quality/caption/audio-track pickers. Shorts already proves the alternative:
`controls=0` plus a class-agnostic hider that re-shows only the `<video>`.

## Decision

Hide YouTube's chrome in the TOS embed (`controls=0` + `TOSPlayerChromeJS`) and
draw a native transport overlay (`TOSPlayerTransportOverlay`) composed from the
shared `PlayerControls` subviews. Expose quality and audio-track through a
defensive JS facade over the embed's own player object (`window.__stPlayerAPI`);
captions come from InnerTube's `captionTracks` and are rendered natively
(`CaptionCueView`), because the TV-UA embed's captions module is not reliable.
Unsupported options are hidden or disabled. Do not migrate to the official
IFrame Player API. Show the actual quality reported by the player; a picker tap
is only a request. Do not hide or skip ads: if `ad-showing` is set, the hider
disables itself so YouTube's ad UI and Skip Ad remain usable, and the native
overlay yields. Ship iOS first; macOS follows. No hybrid AVPlayer handoff
(ADR-0007).

## Consequences

- Good: one visual language for both engines; buffered ranges, chapter markers
  and SponsorBlock markers on the timeline; quality/captions/audio-track return
  to the TOS path where the TV-UA player exposes them.
- Bad: the facade depends on undocumented `movie_player` internals; pickers
  degrade to hidden/disabled controls when those disappear.
- Bad: hiding YouTube chrome is ToS-sensitive. Ads stay visible; no ad-blocking.
- Risk: DOM churn. The hider is class-agnostic and the facade is try/catch
  wrapped, so failures degrade rather than crash.

## Alternatives considered

- **Official IFrame Player API**: documented methods, but changes the player
  bootstrap and risks the error 153 class this player avoids. Deferred.
- **Duplicate TOS-only controls**: drifts from the direct player. Rejected.
- **Hide ads / auto-skip**: rejected — the player exists to stay TOS-compliant.
