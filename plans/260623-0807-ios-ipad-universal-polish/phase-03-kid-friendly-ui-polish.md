---
phase: 3
title: "Kid-Friendly UI Polish"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: [2]
---

# Phase 3: Kid-Friendly UI Polish

## Overview

Make the app feel finished and safe for a 5-year-old: a friendly app icon + name,
big forgiving touch targets, and guards so a child mashing the screen can't break
the flow. Visual polish on top of the working, responsive app.

## Requirements

- Functional: the installed app has a proper icon + display name; touch targets
  are large and forgiving; rapid/stray taps don't open duplicate sessions, cut off
  replies, or leave the app in a stuck state; the dev-only transcript toggle isn't
  a thing a child stumbles into.
- Non-functional: still one codebase; no regression to the voice loop; analyze
  clean; macOS unaffected.

## Architecture

- **App icon + name:** generate a simple LED-robot-face icon; set the iOS display
  name (CFBundleDisplayName, e.g. "Người bạn nhỏ") and the macOS name. Use
  `flutter_launcher_icons` (a dev dependency) or set icons manually.
- **Touch targets:** ensure the talk button + child cards meet a generous min size
  on all devices (already large; confirm on the smallest phone). Add a little press
  feedback (scale/opacity) so a child sees the tap register.
- **Tap guards (extend what exists):**
  - Profile picker already guards double-tap (`Navigator.canPop()`).
  - Talk button: it already locks during connecting/disconnected; add a debounce so
    a rapid double-tap doesn't toggle the mic on→off in one gesture.
  - Consider hiding/locking the dev transcript toggle behind a long-press or a
    hidden gesture so a kid doesn't surface debug UI.
- **Optional:** lock orientation to portrait (steadier for a kid); a gentle
  background; larger, rounder visuals consistent with the robot motif.

## Related Code Files

- Modify: `app/pubspec.yaml` (+ dev dep `flutter_launcher_icons`; icon asset)
- Create: `app/assets/icon/…` (the app icon source)
- Modify: `app/ios/Runner/Info.plist` + macOS Info.plist (display name; orientation)
- Modify: `app/lib/main.dart` (talk-button debounce + press feedback; gate the
  transcript dev toggle; bigger/rounder polish)
- Modify: `app/lib/profile_picker.dart` (press feedback; any sizing polish)

## Implementation Steps

1. App icon: create a simple robot-face icon asset; configure
   `flutter_launcher_icons` (or set manually for iOS + macOS); regenerate.
2. Display name: set the iOS `CFBundleDisplayName` (+ macOS) to a friendly name.
3. Talk button: add a short debounce + visual press feedback; confirm it can't
   double-toggle the mic on a fast tap.
4. Dev transcript toggle: move it behind a non-obvious gesture (e.g. long-press the
   title) so a child won't open it.
5. (Optional) lock portrait orientation; minor visual polish (rounded, spacing).
6. Verify on phone + tablet (+ macOS): icon/name show, taps feel good, no way for a
   kid to get stuck; `flutter analyze` clean; smoke test passes.

## Success Criteria

- [ ] App shows a proper icon + friendly name on iOS (and macOS).
- [ ] Touch targets are large/forgiving; taps give visible feedback.
- [ ] Rapid/stray taps can't open duplicate sessions, cut replies, or stick the UI.
- [ ] The dev transcript toggle isn't trivially reachable by a child.
- [ ] No regression to the voice loop; `flutter analyze` clean; macOS unaffected.

## Risk Assessment

- **Icon tooling fiddliness** (flutter_launcher_icons config) → keep one source PNG;
  if the tool fights, set the iOS AppIcon set manually.
- **Debounce too aggressive** → tune so a deliberate second tap (stop talking) still
  works; only swallow truly rapid double-fires.
- **Hiding the dev toggle too well** → keep a way YOU can reach it (documented
  gesture), just not obvious to a kid.
- **Polish scope creep** → keep it to icon/name + targets + guards; don't redesign
  the whole UI (YAGNI). Character animation already exists.
