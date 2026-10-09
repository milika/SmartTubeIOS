# CasioClockWidget (experimental)

A small Home Screen widget: a live digital clock drawn as a Casio F-91W
(black resin case, blue bezel line, gold labels, grey-green LCD with seven-segment
digits, day/date, PM marker, running seconds). Self-contained Swift package — no
dependencies on any app code, no bundled assets or fonts.

## Add to a project

1. Add this folder as a local package (Xcode: File > Add Package Dependencies… > Add Local…).
2. Link the `CasioClockWidget` library to your **widget extension** target.
3. List it in the extension's `WidgetBundle`:

   ```swift
   import CasioClockWidget

   @main
   struct MyWidgets: WidgetBundle {
       var body: some Widget {
           CasioClockWidget()
       }
   }
   ```

Requires iOS 17 / macOS 14 (uses `containerBackground` and `contentMarginsDisabled`).

## Remove

Delete the `CasioClockWidget()` line and the package dependency.

## How it stays live

- Hours and minutes: a timeline with one entry per minute (an hour at a time).
- Seconds: `Text(date, style: .timer)` counting up from the start of the minute, clipped to
  its last two digits — widgets can't redraw every second, but timer text animates itself.
- 12- or 24-hour follows the device setting; 12-hour shows the hour without a leading zero
  and a PM marker, like the watch.

## Tests

`swift test` in this folder (formatting and timeline entries).
