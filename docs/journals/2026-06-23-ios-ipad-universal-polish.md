# iOS / iPad Universal + Kid UI Polish

**Date:** 2026-06-23
**Plan:** `plans/260623-0807-ios-ipad-universal-polish/` (3 phases, all done)

## Goal

Bring the Flutter voice app from macOS-only to the devices the kids actually use —
**iPhone + iPad (universal)** — and polish it for a 5-year-old.

## What shipped

**Phase 1 — iOS platform:** `flutter create --platforms=ios .` (additive; macOS
untouched); `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`. All three
plugins (`record`, `flutter_pcm_sound`, `web_socket_channel`) already declare iOS
support — no new platform channel; the same Dart code runs on iOS.

**Phase 2 — responsive layout:** a tiny `responsive.dart` (`isTablet` breakpoint);
the profile picker stacks cards vertically on a phone and lays them side-by-side
on a tablet (the old fixed-width Wrap overflowed on iPhone portrait), wrapped in
`SafeArea` + a scroll view; VoiceHome wrapped in `SafeArea`, robot + button scale
per device.

**Phase 3 — kid polish:** app icon (the happy LED robot face, rendered to a 1024px
source + generated via `flutter_launcher_icons`) + display name "Người bạn nhỏ";
talk-button debounce; the dev transcript toggle moved behind a long-press on the
title (invisible to a child); picker keeps its double-tap nav guard.

## Tooling: XcodeBuildMCP + simulator-driven verification

Registered `XcodeBuildMCP` in `.mcp.json` (the pattern from the `my-translator`
project; the binary was already installed globally). Even before that MCP loads
(next session), I verified everything on simulators directly via `flutter build
ios --simulator` + `xcrun simctl install/launch/screenshot`:
- iPhone 17: app launches; picker renders without overflow (cards stacked).
- iPad Pro 13": cards side-by-side, larger title — universal layout confirmed.
- Home screen: the robot icon + "Người bạn nhỏ" name show.

(UI *taps* still need the MCP's ui-automation, which loads next session — so the
picker→voice flow + cold-start UI on-device is the remaining live check.)

## Code review fix

The talk-button debounce was symmetric (500ms gate on every toggle) → a child who
taps start, says one quick word, then taps stop within 500ms would have the **stop
swallowed** (mic stuck open). Made it asymmetric: only a rapid re-OPEN is debounced;
a stop is always honored. Also removed dead `scaled()` + a redundant nested SafeArea.

## State

- iOS/iPad universal + polish: **done, simulator-verified.**
- macOS unaffected; analyze clean; tests pass.

## Carry-forward / open

- **User device step:** Xcode signing (Apple Developer team) + run on a REAL
  iPhone/iPad with the cloud `--dart-define` build, and confirm mic capture +
  the iOS audio session (mic + speaker coexisting — the one iOS risk). Simulators
  can't fully exercise the mic.
- Next session has XcodeBuildMCP live → can drive on-device taps + the full
  picker→talk→memory flow.
- Remaining MVP work: parental PIN + time limit.
