---
phase: 3
title: "ThemeRotation service + parent setting + dwell timer"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: [2]
---

# Phase 3: ThemeRotation service + parent setting + dwell timer

## Overview

Add the device-wide world rotation (NEW behavior, not in the preview): after a
voice session longer than 2 minutes, the next time the picker shows, the world
changes to a random DIFFERENT world. A parent setting toggles Fixed vs Random.
Persisted in `shared_preferences`.

## Requirements

- `ThemeRotation` (a `ChangeNotifier`) in `app/lib/scene/theme_rotation.dart`:
  - State: `String currentWorldId` (default `'night'`), `bool randomPerSession`
    (default `true`).
  - `Future<void> load()` — read both keys from `shared_preferences` (defaults on
    first run). Call before `runApp` (like `DeviceIdentity().ensure()`).
  - `void onSessionEnd(Duration dwell)` — if `!randomPerSession` return; if
    `dwell < 2 min` return; else `currentWorldId = _pickDifferent(currentWorldId)`
    (uniform over the other 5), persist, `notifyListeners()`.
  - `Future<void> setFixed(String worldId)` / `setRandom()` — set mode (+ world for
    fixed), persist, notify.
  - `SceneSpec get spec => specForId(currentWorldId)`.
  - `_pickDifferent`: pick from `allScenes` where `id != current`. Randomness via
    `dart:math Random` is fine HERE (runtime app logic, not a CustomPainter — the
    "no Random in painters" rule is about deterministic paint frames only).
- Wire in `MonamiApp`:
  - `main()` calls `await themeRotation.load()` before `runApp` (alongside
    `DeviceIdentity().ensure()`).
  - Hold the single instance in `_MonamiAppState`; pass `themeRotation.spec` to the
    picker; rebuild the picker when it notifies (AnimatedBuilder/ListenableBuilder)
    so a rotation shows on return.
- Dwell timer in `VoiceHome`:
  - Record `_enteredAt = DateTime.now()` in `initState`.
  - In `_leave()` (the single exit path) compute
    `DateTime.now().difference(_enteredAt)` and call
    `widget.themeRotation.onSessionEnd(dwell)` BEFORE `pop()` (after `shutdown()`).
  - Pass `themeRotation` into `VoiceHome` from `MonamiApp`.
- Parent setting (non-kid):
  - A small gear in the picker top bar (grown-up area) opens a sheet/dialog:
    "Cố định" (pick one of the 6 worlds) | "Đổi mỗi lần chơi" (random per session).
  - Writes via `setFixed`/`setRandom`; the picker reflects the new world.
  - NOT kid-facing (no big theme button in the kid flow).

## Architecture

```
app/lib/scene/theme_rotation.dart   ChangeNotifier + shared_preferences persistence
app/lib/main.dart                   load() before runApp; pass spec to picker;
                                     dwell timer in VoiceHome._leave → onSessionEnd
app/lib/profile_picker.dart         gear → theme setting sheet (setFixed/setRandom)
```

Keys: `theme_world_id` (String), `theme_random_per_session` (bool).

## Related Code Files

- Create: `app/lib/scene/theme_rotation.dart`.
- Modify: `app/lib/main.dart` (load + wire + dwell timer), `app/lib/profile_picker.dart`
  (gear + setting sheet).
- Tests: `app/test/theme_rotation_test.dart` (NEW, Phase 4) — pure-logic unit tests
  with an in-memory SharedPreferences mock.

## Implementation Steps

1. Write `ThemeRotation` (load/onSessionEnd/setFixed/setRandom/_pickDifferent/spec).
2. `main()`: load before runApp; hold instance; pass spec to picker + service to
   VoiceHome; rebuild picker on notify.
3. VoiceHome: `_enteredAt` + `_leave()` → `onSessionEnd(dwell)` before pop.
4. Picker: gear → setting sheet (Fixed world chooser / Random toggle).
5. `flutter analyze` clean.

## Success Criteria

- [ ] First run → world = `night` (or persisted). Persists across restart.
- [ ] Random mode + a >2-min session → picker shows a DIFFERENT world; a <2-min
  session → unchanged.
- [ ] Fixed mode → world never auto-changes; the chosen world persists.
- [ ] `_pickDifferent` never returns the current id; always one of the other 5.
- [ ] Setting is reachable only via the grown-up gear (not a kid button).

## Risk Assessment

- **Persistence race at launch** → `await load()` before `runApp` (proven pattern).
- **Dwell measured on the wrong boundary** → anchor on screen push (`initState`) →
  pop (`_leave`); `_leave` is the only exit (PopScope intercepts back/swipe).
- **Rotation feels repetitive** → spec says "≠ current" only; revisit later if
  repeats annoy (documented in plan §10).
- **Rollback:** the service is additive; remove the wiring → screens fall back to a
  fixed `specForId('night')`. No data migration.
