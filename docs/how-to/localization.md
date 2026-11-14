> status: current (2026-11-14)

# Localization

## How it is wired

There is exactly **one** string catalog for every target:

```
SmartTubeIOS/Sources/SmartTubeIOSCore/Localizable.xcstrings
```

It lives in the `SmartTubeIOSCore` resource bundle so the app, its extensions and the
widget can all resolve the same keys. The catalog declares 16 languages: `ar`, `de`,
`en` (source), `es`, `fr`, `hi`, `hr`, `id`, `it`, `ja`, `ko`, `pt-BR`, `ru`,
`sr`, `tr`, `zh-Hans`.

Two things are required for a string to actually appear translated:

1. **Resolve it through the package bundle.** SwiftUI string initializers default to
   `Bundle.main`, which contains no catalog. `SmartTubeIOSCore` exposes:

   ```swift
   public enum L10n {
       public static let bundle: Bundle        // the catalog's bundle
       public static func string(_ key: String.LocalizationValue) -> String
   }
   ```

   ```swift
   Text("Watch Later", bundle: L10n.bundle)          // LocalizedStringKey sites
   Button(L10n.string("Sign In")) { … }              // String parameters
   return L10n.string("Skipped \(category)")          // String-returning helpers
   LocalizedStringResource("Open Video", bundle: L10n.bundle)  // App Intents
   ```

   Never use `bundle: .module` inside the `SmartTubeIOS` UI target — that bundle has no
   catalog.

2. **Declare the languages in the app's Info.plist.** iOS picks the app language from
   `CFBundleLocalizations`; without the declaration the app runs in `en` even when the
   device is Chinese and every lookup falls back to English. The same array is present
   in the iOS/macOS app, Share/Safari extensions, the download widget and the tvOS app.

Run `just localization-check` after changing strings: it fails when a declared language
is missing a key or a translation drops/reorders a printf placeholder. It is part of
`just ci`.

## Developer workflow (new string)

1. Write the English text through `L10n` as shown above. The key **is** the English
   text (including `%@`/`%lld` placeholders), e.g. `L10n.string("Scheduled: Today, %@")`.
2. Add the key to the catalog. Xcode's "Extract Localized Strings" does this when you
   build in the IDE; with xcodebuild only, add the JSON entry by hand or let the
   coverage check list it.
3. Fill the other 14 languages with the script below.
4. Write the `zh-Hans` value by hand (or with an LLM) following the glossary — Chinese
   is not machine-translated.

## Automation (non-Chinese languages)

```bash
cd SmartTubeIOS/Sources/SmartTubeIOS
python3 translate_strings.py                       # fill missing keys (no venv needed)
python3 translate_strings.py --dry-run             # preview what would be filled
python3 translate_strings.py --langs de,fr         # restrict to some locales
python3 translate_strings.py --fix-lang sr         # overwrite one whole language
```

The script is additive, uses Google's public `translate_a/single` endpoint through
`urllib` (stdlib only, no API key), protects printf placeholders with `⟪0⟫`-style
tokens, and paces requests with a shared rate limiter (bursts trigger HTTP 429).
If Google throttles an IP, wait a few minutes and rerun — it resumes where it left off.

Add a language to `LANG_MAP`, to the catalog, to `CFBundleLocalizations` in every
Info.plist and to `knownRegions` in `project.pbxproj`.

## Chinese (zh-Hans) glossary

Mainland Simplified Chinese, concise UI style (no subjects, verb-first, full-width
punctuation). Fixed terms:

| English | zh-Hans |
|---|---|
| Playlist | 播放列表 |
| Subscriptions | 订阅 |
| Watch Later | 稍后观看 |
| Library | 资料库 |
| Home | 首页 |
| Sign in / Sign out | 登录 / 退出登录 |
| Downloads | 下载 |
| History / Watch History | 历史记录 / 观看历史 |
| Settings / Search / Comments / Channel | 设置 / 搜索 / 评论 / 频道 |
| Quality / Captions / Audio track | 画质 / 字幕 / 音轨 |
| Play / Pause / Skip / Mute | 播放 / 暂停 / 跳过 / 静音 |

Kept in English: `SmartTube`, `YouTube`, `Shorts`, `DeArrow`, `SponsorBlock`, `PIN`,
`4K/8K`, `HDR`, `HLS`, `DASH`, `PiP`, `Liquid Glass`, and printf placeholders.

## Checking coverage

```bash
just localization-check          # python3 scripts/check-localizations.py
```

It prints per-language coverage and fails on missing keys or placeholder mismatches.

## Known limitations

- **Siri spoken phrases** — `AppShortcut(phrases:)` only accepts string literals that
  resolve against the main bundle; there is no catalog there, so phrases stay English.
  Intent titles, descriptions, parameters and `shortTitle` are localized.
- **Info.plist strings** (permission prompts, extension display names) need
  `InfoPlist.strings` files inside each target; those require project-file changes and
  are not localized yet.
- **Safari extension UI** is JavaScript (`background.js`/`content.js`) and only shows the
  brand name.
- **Plurals** — the catalog has no plural variations (Chinese has none). `%lld video%@`
  keeps an English plural suffix placeholder for other languages; fix at the source
  before adding plural entries.
- **Machine translation quality** — non-Chinese values come from Google Translate; long
  or idiomatic strings may need native review.

## Screenshots

Chinese UI acceptance screenshots live in `docs/screenshots/zh-Hans/`.
