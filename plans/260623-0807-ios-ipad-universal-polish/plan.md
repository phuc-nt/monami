---
title: "iOS iPad Universal And Kid UI Polish"
description: "Bring the Flutter voice app to iPhone + iPad (universal): add the iOS platform + mic permission + signing, make the layout responsive for both sizes, and polish the UI for a 5-year-old (big touch targets, app icon/name, prevent stray taps)."
status: completed
priority: P2
created: 2026-06-23
blockedBy: [260622-2337-deploy-cloud-run]
---

# iOS iPad Universal And Kid UI Polish

## Overview

The app currently runs on **macOS desktop only**. Bring it to the devices the
kids actually use — **iPhone + iPad (universal)** — and make it feel right for a
5-year-old: add the iOS platform with mic permission + signing, a responsive
layout that looks good on a small phone and a large tablet, and kid-friendly
polish (large touch targets, an app icon + name, and guards against stray/rapid
taps). The backend is already on Cloud Run; the app connects to it via the
existing `--dart-define` config.

## Decided scope

- **Universal:** runs on iPhone AND iPad; layout adapts to screen size.
- **Goal:** runs on the user's real devices (paid Apple Developer account → no
  7-day re-sign limit) AND a kid-UI polish pass.
- **Plugins already iOS-ready** (verified): `record`, `flutter_pcm_sound`,
  `web_socket_channel` all declare iOS support → no new platform channel needed;
  the same Dart code runs on iOS.

## Architecture / what changes

```
Existing Dart code (voice_controller, voice_socket, audio_capture/playback,
robot_face, profile_picker, main) is platform-agnostic and unchanged in logic.
New: ios/ platform (flutter create --platforms=ios .), iOS mic permission +
signing, a responsive layout wrapper (phone vs tablet), and polish assets
(icon, name) + interaction guards.
```

Current touchpoints (from scout):
- `app/` has only `macos/`. Add `ios/` via `flutter create --platforms=ios .`.
- iOS mic permission goes in `ios/Runner/Info.plist` (NSMicrophoneUsageDescription),
  mirroring the macOS entitlement.
- Layout: `main.dart` (VoiceHome) + `profile_picker.dart` currently use fixed
  sizes (e.g. card width 220, maxWidth 560) → make responsive with LayoutBuilder /
  MediaQuery.
- Polish: app icon + display name (iOS), bigger touch targets, rapid-tap guards
  (the profile picker already guards double-tap; extend to the talk button if
  needed), and orientation lock if wanted.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Add iOS Platform And Audio Permissions](./phase-01-add-ios-platform-and-audio-permissions.md) | ✅ Completed |
| 2 | [Responsive Universal Layout](./phase-02-responsive-universal-layout.md) | ✅ Completed |
| 3 | [Kid-Friendly UI Polish](./phase-03-kid-friendly-ui-polish.md) | ✅ Completed |

> **Done + simulator-verified.** Added the iOS platform (`flutter create
> --platforms=ios`), mic permission, app icon (robot face) + name ("Người bạn
> nhỏ"). Responsive: picker stacks on iPhone / side-by-side on iPad (overflow bug
> fixed), SafeArea, robot+button scale per device. Kid guards: talk-button
> debounce (asymmetric — stop always honored), dev transcript toggle hidden behind
> a title long-press, picker double-tap nav guard (prior). Verified on iPhone 17 +
> iPad Pro simulators (screenshots): picker no overflow on both; icon + name on the
> iOS home screen. Registered XcodeBuildMCP in `.mcp.json` for future sim/device
> automation. macOS unaffected; analyze clean; tests pass.
>
> **Still a USER device step:** signing with the Apple Developer team in Xcode +
> running on a REAL iPhone/iPad (the cloud `--dart-define` build) + the on-device
> mic/playback audio-session test. The simulator proved build + layout + icon; a
> real device confirms mic capture + the audio session (the one iOS risk noted).

## Acceptance criteria (whole plan)

- The app builds + runs on an iPhone AND an iPad (real devices, signed).
- Mic permission prompts on iOS; capture + playback work (full spoken loop to the
  cloud backend).
- Layout looks good on both a phone and a tablet (no overflow, robot face + button
  sized sensibly for each).
- Kid polish: large tap targets, an app icon + friendly name, no easy way for a
  child to break the flow with stray/rapid taps.
- macOS build still works (no regression); `flutter analyze` clean; tests pass.

## Scope OUT (later)

App Store submission/review; Android; push notifications; offline mode; parental
PIN + time limit (separate plan); deep-linking; iPad multitasking/split-view
tuning; localization beyond the current VN/EN UI strings.

## Dependencies

- Blocked by (satisfied): cloud deploy (the app targets the Cloud Run backend).
- External: Xcode (present), a paid Apple Developer account (have), a real iPhone
  and/or iPad to test on. CocoaPods (present).
- No new Dart packages expected.

## Open questions (resolve during execution)

1. Orientation: lock to portrait (simplest for a kid) or allow landscape on iPad?
   Default: portrait-first; revisit for iPad.
2. App icon source: generate a simple robot-face icon, or use a placeholder for
   now? Default: a simple generated icon (the LED robot motif).
3. iOS audio session category: `flutter_pcm_sound` sets one (playback); confirm
   capture + playback coexist on iOS (mic + speaker) — verify in the device test.
4. Signing: use automatic signing with the Apple Developer team in Xcode; capture
   the team id / bundle id without committing anything sensitive.
