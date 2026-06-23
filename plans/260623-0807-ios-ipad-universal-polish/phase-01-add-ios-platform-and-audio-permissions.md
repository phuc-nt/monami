---
phase: 1
title: "Add iOS Platform And Audio Permissions"
status: completed
priority: P2
effort: "0.5d"
dependencies: []
---

# Phase 1: Add iOS Platform And Audio Permissions

## Overview

Add the iOS platform to the existing Flutter app, wire the mic permission +
signing, and get a full spoken loop running on a real iPhone/iPad against the
cloud backend. No UI changes yet (that's Phase 2/3) — just "it runs on iOS".

## Requirements

- Functional: `ios/` platform exists; the app builds + installs on a real device;
  iOS prompts for mic permission; capture (16k PCM) + playback (24k PCM) both work;
  a full conversation to the Cloud Run backend succeeds (with the `--dart-define`
  URL + token).
- Non-functional: macOS build still works; signed with the Apple Developer team;
  nothing sensitive committed.

## Architecture

- `flutter create --platforms=ios .` (run inside `app/`) generates `ios/` without
  touching existing platforms/code.
- `ios/Runner/Info.plist`: add `NSMicrophoneUsageDescription` (mirror the macOS
  mic string) so iOS shows the permission prompt.
- Signing: open `ios/Runner.xcworkspace` in Xcode, set the Apple Developer **team**
  + a unique **bundle id** (e.g. `com.<you>.monami`), automatic signing. Capture
  the bundle id in the plan, not secrets.
- iOS audio session: `flutter_pcm_sound` configures a playback category; `record`
  needs mic. Verify both coexist (mic + speaker) on a real device — the iOS audio
  session may need the right category (playAndRecord) if playback mutes capture or
  vice versa. Adjust if the device test shows a conflict.

## Related Code Files

- Create: `app/ios/` (generated platform; Runner project, Info.plist, etc.)
- Modify: `app/ios/Runner/Info.plist` (NSMicrophoneUsageDescription)
- Modify: `app/README.md` (iOS run/sign note; device build command with --dart-define)
- (No Dart logic changes — the plugins are iOS-ready.)

## Implementation Steps

1. In `app/`, run `flutter create --platforms=ios .` (additive; keeps macOS).
2. Add `NSMicrophoneUsageDescription` to `ios/Runner/Info.plist`.
3. `flutter pub get`; `cd ios && pod install` (CocoaPods present) if needed.
4. In Xcode: select the dev team, set the bundle id, enable automatic signing.
5. Build + run on a real device:
   `flutter run -d <device-id> --dart-define=MONAMI_WS_BASE=… --dart-define=MONAMI_TOKEN=…`
6. Grant mic permission; confirm a full spoken loop to the cloud works (transcript
   + reply + memory). If mic/playback conflict, set the iOS audio session category
   (playAndRecord) and re-test.
7. Confirm `flutter build macos` still works (no regression).

## Success Criteria

- [ ] `ios/` platform added; `flutter build ios` (or device run) succeeds, signed.
- [ ] iOS prompts for mic; capture + playback both work on a real device.
- [ ] Full spoken loop to the Cloud Run backend works on iPhone and/or iPad.
- [ ] macOS build unaffected; `flutter analyze` clean.
- [ ] Bundle id documented; nothing sensitive committed.

## Risk Assessment

- **Mic + playback audio-session conflict on iOS** → set the AVAudioSession
  category to playAndRecord; verify on a real device (this is the top iOS risk).
- **Signing friction** → automatic signing with the paid team; a unique bundle id;
  trust the dev cert on the device once.
- **Plugin iOS build issues** (Pods) → `pod install`, clean build; all three
  plugins declare iOS support (verified), so this should be smooth.
- **Cold start over cellular/wifi on device** → already handled by the connecting
  UI; just confirm it behaves on a real network.
