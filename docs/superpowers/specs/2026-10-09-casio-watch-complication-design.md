# Casio complication for Apple Watch — design

Date: 2026-10-09. Status: approved (owner). Builds on
`2026-10-09-casio-widget-models-design.md` (package `Widgets/CasioClockWidget/`).

## Goal

Show the Casio F-91W LCD on Apple Watch faces. Apple allows no third-party watch faces, so
this is a **rectangular complication** (WidgetKit `accessoryRectangular`: the large slot of
Modular, Modular Duo, Infograph Modular, and the Smart Stack). Owner: "we don't want the main
YouTube app on the watch, choose the minimum needed to support watch faces only".

Out of scope: circular / corner / inline complications, a full-screen watch face app, the
light (watch complications can't run a tap action; a tap opens the app), YouTube on the watch.

## What ships

- **Watch app "SmartTube"** (bundle `com.void.smarttube.app.watchkitapp`, watchOS 10+),
  embedded in the iPhone app (same TestFlight / App Store build; installs with the iPhone app
  when the user has automatic watch-app installs on). One screen: a preview of the complication
  and how to add it ("Touch and hold the watch face, tap Edit, swipe to Complications, pick a
  large slot, choose SmartTube"). No networking, no YouTube code; English only.
- **Complication extension** (`….watchkitapp.complications`) inside the watch app, listing
  `CasioF91WComplication()`.
- Version and build numbers equal the iPhone app's (the upload script bumps every
  `CURRENT_PROJECT_VERSION` in the project).

## Package changes

- `Package.swift`: add `.watchOS(.v10)`.
- iPhone-only code (`CasioWatchWidget`, `CasioF91WWidget`, its `#Preview`) inside
  `#if !os(watchOS)` (`.systemSmall` doesn't exist on watchOS).
- `protocol CasioComplicationModel: CasioModel` with `complicationKind` (stable, distinct from
  the iPhone kind) and `rectangularComplication(_ context: CasioFaceContext) -> some View`.
  `CasioModels.complications` lists them; tests check all kinds are unique.
- `Widget/CasioComplicationWidget.swift` (watchOS only): internal generic
  `CasioComplicationWidget<Model>`: `StaticConfiguration(kind: Model.complicationKind,
  provider: CasioClockProvider(model: Model.complicationKind))`, family
  `.accessoryRectangular`, container background clear, gallery name/description from the model.
- `Models/F91W/F91WComplication.swift`: the F-91W layout on a 200×80 canvas (FaceCanvas):
  top row `PM`/`24H`, weekday (DSEG14) and date (DSEG7); bottom row H:MM (DSEG7, squeezed 0.9)
  and live seconds (LiveSeconds). Full-colour faces: grey-green glass and dark ink, as on the
  iPhone. Tinted faces (`widgetRenderingMode == .accented`): no glass, white ink marked
  `widgetAccentable()`, faint unlit segments.
- `Models/F91W/CasioF91WComplication.swift` (watchOS only): public wrapper, plus a `#Preview`.

## Project changes (`SmartTubeApp/SmartTubeApp.xcodeproj`, via the `xcodeproj` gem)

- Target `SmartTubeWatch` (watchOS app): `SmartTubeApp/Watch/` (`SmartTubeWatchApp.swift`,
  `Assets.xcassets` with a 1024 AppIcon from the iPhone icon). Generated Info.plist:
  display name SmartTube, `WKCompanionAppBundleIdentifier = com.void.smarttube.app`,
  `WKRunsIndependentlyOfCompanionApp = NO`. Links `CasioClockWidget` (for the preview).
  Embeds the complication extension (Embed Foundation Extensions).
- Target `SmartTubeWatchComplications` (watchOS app extension): `SmartTubeApp/WatchComplications/`
  (`CasioComplications.swift` WidgetBundle, `Info.plist` with
  `NSExtensionPointIdentifier = com.apple.widgetkit-extension`). Links `CasioClockWidget`.
- iPhone app target: "Embed Watch Content" phase (`$(CONTENTS_FOLDER_PATH)/Watch`) and a target
  dependency on `SmartTubeWatch`, both `platformFilter = ios` (the target also builds for macOS).
- Team, automatic signing, `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` as the iPhone app.

## Testing

- Package: `swift test` (kinds unique across iPhone and watch widgets); `swift build` for
  watchOS (`xcodebuild -scheme CasioClockWidget -destination 'generic/platform=watchOS'`).
- macOS render of the complication in both styles to check the layout.
- App: iOS build includes `Watch/SmartTube.app` with the extension inside.
- Simulator: an Apple Watch simulator paired with "SmartTube Verify"; install the watch app,
  screenshot its screen (live preview) and, if the face editor can be driven, the complication
  on a Modular face.
