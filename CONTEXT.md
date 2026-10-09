# Domain glossary

One line per term, with rejected synonyms in parens where a wrong word has been used before.
Naming a new module after a concept not listed here requires adding the term in the same PR
(`docs/README.md`).

## Domain terms

- **Video** — a single YouTube video, the base content unit.
- **Short** — a vertical, short-form video; classified independently by 7 renderer parsers plus a
  `duration <= 180` heuristic (a known duplication, `docs/modernization/AUDIT.md` §2.1).
- **Feed / Feed row / Continuation** — a screen section (Home, Subscriptions, Search results, …)
  is a *feed*; a horizontal group within it is a *row*; the pagination token to fetch more of a
  feed is a *continuation*.
- **Stream source / Stream method** — one way of resolving a playable URL for a video (e.g. iOS
  HLS, DASH composition, embed, yt-dlp-style, n-descrambled). *Rejected*: "playback method",
  "fallback path" — both blur the distinction between a method and the cascade that orders them.
- **Client profile** — an InnerTube client context: WEB, iOS, TVHTML5, MWEB, Android, AndroidVR,
  VisionOS, WebSafari, WebCreator. Each has its own auth rules, API key, and available fields.
- **PoToken / BotGuard** — the proof-of-origin token YouTube requires for some playback requests,
  and the JS-challenge-solving pipeline (`BotGuardWebViewRunner`, `BotGuardClient`) that obtains it.
- **TOS player** — the WKWebView-hosted YouTube IFrame embed player (`TOSPlayerViewModel`),
  default on iOS since ADR-0006. "TOS" = terms-of-service-compliant (YouTube's own player, not a
  stream-extraction pipeline).
- **AVPlayer path** — the non-TOS playback path: resolve a raw stream URL, hand it to AVPlayer.
  Still used on tvOS and for some iOS Shorts cases.
- **Shorts embed player** — the WKWebView/iframe pipeline specifically for Shorts
  (`ShortsEmbedPlayerViewModel`), distinct from the TOS player though architecturally similar.
- **Playback session** — planned (WS5, not yet implemented): one interface shared by AVPlayer,
  TOS, and Shorts players so SponsorBlock/watch-history/Now-Playing wiring isn't tripled.
- **Player engine** — the underlying playback technology (AVPlayer vs. WKWebView/IFrame) as
  distinct from the view model that drives it.
- **Queue** — the ordered list of upcoming videos (`CurrentQueueStore`), independent of any one
  feed.
- **Watch state / Watch history / Watchtime reporting** — *watch state* is per-video playback
  position (`VideoStateStore`); *watch history* is the list of previously-watched videos reported
  to YouTube; *watchtime reporting* is the periodic InnerTube checkpoint call
  (`WatchtimeTracker`) that attributes viewing time to a signed-in account.
- **SponsorBlock segment / Skip decision** — a *segment* is a timestamped range from the
  SponsorBlock API (sponsor, intro, outro, …); a *skip decision* is what
  `SponsorBlockDecisionEngine.decide` returns for a given playback position (skip / show toast /
  do nothing).
- **DeArrow branding** — community-submitted alternative titles/thumbnails from the DeArrow API.
- **Local subscription** — a followed channel that doesn't require Google sign-in (as opposed to
  a YouTube-account subscription).
- **RSS feed** — a channel feed added by RSS URL rather than by subscribing via YouTube.
- **Quality (ABR hint, cap, override)** — *ABR hint* nudges adaptive bitrate selection; a *cap*
  is a hard ceiling (e.g. "never above 1080p"); an *override* is a per-video manual quality pin.
  None of these apply on the TOS-player path (YouTube's own player owns ABR there — ADR-0006).
- **Audio track / Caption track** — a selectable dubbed-audio or subtitle track on a video.
- **Deep link / Pending action** — a *deep link* is an external entry point (share extension,
  Siri, Safari extension, URL scheme) that names a video/channel to open; a *pending action* is
  the queued intent (e.g. "open this video") waiting for the app to be ready to act on it.
- **Live suite / Smoke suite** — a *Live* UI-test suite hits real YouTube over the network; a
  *Smoke* suite (WS3-T3.4, not yet implemented) is hermetic and stubbed, safe to run on every PR.

## Casio clock widgets (`Widgets/CasioClockWidget`)

- **Watch model** — one Casio watch the package draws (`CasioF91W`, `CasioGMWB5000`, …): its
  widget kind, canvas measured from a reference photo, palette and face. *Rejected*: "watch face"
  for the model (Apple's *watch faces* are the watchOS faces our complication sits on).
- **Catalogue** — the single list of what the package publishes (`CasioCatalogue.swift`): the
  model registry and the Home Screen widgets / watch complications built from it. Registering a
  watch model happens only there; the app's extensions list the catalogue once.
- **LCD module / Module display** — Casio builds one *LCD module* (numbered: 593, 3459, 240)
  into several watches; its *module display* (`Module593Display`, …, an `LCDModuleDisplay`) is
  that LCD's layout, measured once and placed in each watch model's glass. A *face* draws the
  case around it. *Rejected*: "screen" (the whole widget), "face" for the display.
- **Live clock** — how a widget shows the time to the second although WidgetKit redraws only at
  timeline entries: hourly entries for the hours, one self-animating timer ("10:MM:SS") for
  minutes and seconds (`LiveClock/`). *Rejected*: "minute timeline" (the old one-entry-per-minute
  design, removed for archive size).

## Architecture vocabulary

From the `improve-codebase-architecture` skill's `LANGUAGE.md` — use these exactly; never
substitute "component," "service," "API," or "boundary."

- **Module** — anything with an interface and an implementation (function, class, package, or a
  tier-spanning slice).
- **Interface** — everything a caller must know to use a module correctly: type signature, plus
  invariants, ordering constraints, error modes, required configuration, performance.
- **Seam** — a place where behaviour can be altered without editing in that place (Feathers).
- **Adapter** — a concrete thing that satisfies an interface at a seam.
- **Depth** — leverage at the interface: how much behaviour a caller gets per unit of interface
  they have to learn. Deep = small interface, large behaviour. Shallow = the opposite.
- **Leverage** — what callers get from depth: one implementation paying back across many call
  sites and tests.
- **Locality** — how close together the pieces someone needs to understand or change a behaviour
  live, versus scattered across the codebase.
