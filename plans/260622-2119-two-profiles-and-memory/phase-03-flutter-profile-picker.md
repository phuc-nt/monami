---
phase: 3
title: "Flutter Profile Picker"
status: pending
priority: P2
effort: "0.5d"
dependencies: [1]
---

# Phase 3: Flutter Profile Picker

## Overview

A friendly first screen where the child taps who they are (Vy or Phong); the app
then opens the voice screen for that child, passing the chosen `profile_id` so the
backend loads the right profile + memory. Big, simple, kid-tappable.

## Requirements

- Functional: on launch show a picker with two big tappable cards (name + a simple
  avatar/color, e.g. the robot face tinted per child). Tapping one opens the
  existing voice screen wired to that `profileId`. A "back/switch child" affordance
  returns to the picker (closes the session).
- Non-functional: no regression to the voice loop; the picker is the new home,
  `VoiceHome` becomes a pushed route parameterized by `profileId`.

## Architecture

- New `app/lib/profile_picker.dart`: the picker screen; a small `ChildOption`
  list ({id, name, color}) — keep it in sync with the backend ids (`vy`, `phong`).
- `main.dart`: home becomes `ProfilePicker`; selecting a child navigates to
  `VoiceHome(profileId: id)`.
- `voice_controller.dart`: `VoiceController({required String profileId, url})` —
  include `?profile=<id>` in the WS URL.
- `voice_socket.dart` already takes a URL; no change beyond the URL the controller
  builds.
- A "switch child" button (e.g. in the AppBar) pops back to the picker and disposes
  the controller (closing the session → backend summarizes for that child).

## Related Code Files

- Create: `app/lib/profile_picker.dart` (picker screen + child options)
- Modify: `app/lib/main.dart` (home = picker; route to VoiceHome with profileId)
- Modify: `app/lib/voice_controller.dart` (require profileId; add to WS URL)
- Modify: `app/test/widget_test.dart` (smoke test the picker renders; VoiceHome now
  needs a profileId)

## Implementation Steps

1. `profile_picker.dart`: two large cards (Vy, Phong) with name + tinted robot face
   or color; onTap → navigate to `VoiceHome(profileId)`.
2. `main.dart`: set `ProfilePicker` as home; wire navigation.
3. `voice_controller.dart`: require `profileId`; build `ws://…/ws/voice?profile=<id>`.
4. Add a "switch child" action in `VoiceHome` that pops to the picker (disposes the
   controller → ends the session).
5. Update the smoke test for the new home + parameterized `VoiceHome`.
6. Verify end to end (with backend running): pick Vy → talk → it greets Vy; switch
   to Phong → it greets Phong; memory persists per child across picks.

## Success Criteria

- [ ] Launch shows a 2-child picker; tapping opens the voice screen for that child.
- [ ] The chosen child's `profile` reaches the backend (right name greeted).
- [ ] "Switch child" returns to the picker and starts a fresh session for the other.
- [ ] `flutter analyze` clean; smoke test passes; macOS build OK.
- [ ] Voice loop + robot face unaffected.

## Risk Assessment

- **Picker ids drift from backend ids** → keep the two ids (`vy`, `phong`) as the
  contract; document them in both the picker and `backend/child_profile.py`.
- **Switching child leaks the old session** → ensure popping to the picker disposes
  the `VoiceController` (mic/socket/playback closed) before starting a new one.
- **Kid taps rapidly / double-navigation** → guard navigation so one tap = one push.
