# SmartTube

A native Swift/SwiftUI YouTube client for **iPhone**, **iPad**, **macOS**, and **Apple TV**.  
Zero ads. SponsorBlock auto-skip. DeArrow community titles. Google sign-in. Up to 8K.

[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-black?logo=apple)](https://apps.apple.com/us/app/smart-tube-bdp/id6761388918) [![tvOS 17+](https://img.shields.io/badge/tvOS-17%2B-black?logo=apple)](https://apps.apple.com/us/app/smart-tube-bdp/id6761388918) [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://apps.apple.com/us/app/smart-tube-bdp/id6761388918) [![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org) [![Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/milikadelic)

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/us/app/smart-tube-bdp/id6761388918)

Inspired by the original [SmartTube Android app](https://github.com/yuliskov/SmartTube).

---

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/home.png" width="160"/></td>
    <td><img src="docs/screenshots/subscriptions.png" width="160"/></td>
    <td><img src="docs/screenshots/player.png" width="160"/></td>
    <td><img src="docs/screenshots/player-menu.png" width="160"/></td>
    <td><img src="docs/screenshots/settings.png" width="160"/></td>
  </tr>
</table>

---

## Features

### Playback
- Adaptive HLS and DASH streaming — up to 8K via AVPlayer; manual quality picker (144p → 4K)
- DASH adaptive quality switching via `AVMutableComposition` — no black frames, audio preserved on every switch
- Audio-only playback mode
- Landscape playback with one-tap orientation lock (iPhone)
- Picture-in-Picture (iOS)
- Mini-player with background audio
- Adjustable playback speed, seek interval, and sleep timer
- Previous / next video navigation
- Now Playing metadata on lock screen and Dynamic Island

### Audio & Captions
- Multi-track audio selection with a preferred-language setting (original, English, dubbed, and more)
- Caption / subtitle track selection — language choice remembered across videos

### Content & Feeds
- Home, Subscriptions, Shorts, History, Search, Playlists, Library
- Local subscriptions — follow channels without a Google account
- RSS channel feeds with background refresh and deduplication
- iCloud sync for subscriptions, watch state, queue, and RSS feeds
- Video publish date shown in search results and feed cards

### Ad & Sponsor Blocking
- Zero ads, no tracking
- SponsorBlock — auto-skip with per-category controls and skip-button toast
- DeArrow community titles and thumbnails

### Integrations
- Google OAuth sign-in (YouTube TV device-code flow)
- Safari Web Extension — auto-redirects YouTube, Shorts, and Music links to SmartTube
- Share Extension — share YouTube links from any app directly into SmartTube
- Video downloads with live-activity progress; Downloads screen in Library
- WatchTime reporting and Like / Dislike support
- VPN / IP-block detection with a clear, non-retrying error banner
- Comments, Stats for Nerds

### Platforms
- **iPhone & iPad** — iOS 17+
- **macOS** — Mac Catalyst, macOS 14+ (Sonoma)
- **Apple TV** — tvOS 17+, full Siri Remote / d-pad navigation

---

## Project Structure

```
SmartTubeIOS/          Swift Package — core library (models, InnerTube API, SponsorBlock, views)
SmartTubeApp/          Xcode project — app targets (iOS/iPadOS/macOS + Apple TV)
SmartTube.xcworkspace/ Xcode workspace (references both above)
```

---

## Requirements

| Platform | Minimum |
|---|---|
| iOS / iPadOS | 17.0 |
| macOS | 14.0 (Sonoma) |
| tvOS | 17.0 |
| Xcode | 16.0 |
| Swift | 6.0 |

---

## Getting Started

```bash
git clone https://github.com/milika/SmartTubeIOS
cd SmartTubeIOS
open SmartTube.xcworkspace
```

### Signing and bundle identity

Signing and identity are defined **once**, in [`SmartTubeApp/Config/Base.xcconfig`](SmartTubeApp/Config/Base.xcconfig):
`SMARTTUBE_TEAM_ID` and `SMARTTUBE_BUNDLE_PREFIX`. Every bundle ID, the App Group, the
ubiquity KV store and the tvOS team are derived from those two, and the entitlements and
Info.plists reference them — so nothing else in the project should contain a team or bundle
ID. `just identity` prints what each target will actually build with, and `just ci`
(`scripts/check-identity.sh`) fails if any of it is hardcoded back into `project.pbxproj`.

To build under your own team, or under a fork's identity, copy
`SmartTubeApp/Config/Secrets.xcconfig.example` to `SmartTubeApp/Config/Secrets.xcconfig`
(gitignored) and uncomment the two inputs you need:

```
SMARTTUBE_TEAM_ID = YOUR_TEAM_ID
SMARTTUBE_BUNDLE_PREFIX = com.yourdomain
```

Changing the prefix changes the app's identity: it needs its own App Group registered in the
developer portal, its own App Store Connect record, and a `GoogleService-Info.plist` whose
`BUNDLE_ID` matches the new bundle identifier (otherwise Firebase and the Crashlytics dSYM
upload are skipped, with a build warning).

Add your own `GoogleService-Info.plist` to both `SmartTubeApp/SmartTubeApp/` (iOS) and `SmartTubeApp/Smart Tube/` (tvOS) (create a free Firebase project at [console.firebase.google.com](https://console.firebase.google.com) — only Analytics and Crashlytics are used).  
All of these files are gitignored (via glob rules matching any `GoogleService-Info.plist` or `Secrets.xcconfig`) and will never be committed; `setup.sh` installs them for you if you have access to the private config repo.

---

## Contributing

Pull requests are welcome. See [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) for the checklist.  
Please ensure `Secrets.xcconfig` and `GoogleService-Info.plist` are **never** included in a PR.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full version history.

---

## Support

If SmartTube is useful to you and you'd like to support its development, there's a [Ko-fi](https://ko-fi.com/milikadelic).

---

## License

[GPL-3.0](LICENSE)
