---
title: Sticker-Scene UI Upgrade
description: >-
  Replace the app's dark theme with the approved flat-art "Sticker Scene" look:
  6 illustrated worlds (CustomPainter), a standing robot character, comic speech
  bubble, confetti celebrate, and a device-wide ThemeRotation that swaps worlds
  after a long voice session. Ports preview/lib/ onto the real 3 kid screens while
  preserving every shipped data/state/red-team contract.
status: completed
priority: P2
created: 2026-06-25T20:11:00.000Z
blockedBy: []
blocks: []
---

# Sticker-Scene UI Upgrade

## Overview

Port the approved `preview/lib/` flat-art UI ("Sticker Scene", 6 worlds) onto the
real app. The robot stays an LED-faced character standing in a hand-drawn world
with a comic speech bubble; worlds differ only in a painted backdrop + accent
colors. Replaces the current dark theme. ALL real behavior/contracts are kept —
this is a restyle + one new feature (theme rotation), not a logic rewrite.

Source spec: `preview/HANDOFF-SPEC.md`. Source code: `preview/lib/`.

## Decisions (locked with user)

- Spec §10 defaults: theme setting = a small gear in the picker's grown-up area;
  first-run default world = `night`; rotation avoids only the CURRENT world.
- Tests: UPDATE the render/state widget tests to the new UI; keep behavioral tests
  (guest URL, echo gate, model, service, learning_mode, device_identity,
  app_config) unchanged.
- Scope: FULL spec incl. `ThemeRotation` + parent setting + dwell timer.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Deps + flat-art kit + robot-face merge](./phase-01-deps-kit-face-merge.md) | Completed |
| 2 | [Restyle picker + voice + form (real data/state)](./phase-02-restyle-kid-screens.md) | Completed |
| 3 | [ThemeRotation service + parent setting + dwell timer](./phase-03-theme-rotation.md) | Completed |
| 4 | [Update widget tests to the new UI](./phase-04-update-widget-tests.md) | Completed |

## Implementation status (cook)

All 4 phases implemented + verified. `flutter analyze` clean; `flutter test` →
**60 pass** (was 54). One `code-reviewer` gate: DONE_WITH_CONCERNS, no Critical/
High code defects; all 10 hard contracts honored (verified by walk). Review fixes
applied: picker error-state widget test (H1), gender-missing + 409 form tests
(M2), form `_save` re-entry guard (M3), confetti rising-edge (L1), phantom
talk-lock test removed (M1, lock is enforced+tested at the controller boundary).
Baloo 2 bundled as an asset (offline-safe font, no runtime fetch). NO device
build/TestFlight yet — that remains a separate user-gated step (`app/RELEASE.md`).
Report: `plans/reports/cook-260625-2011-sticker-scene-ui-upgrade-progress-report.md`.

## Dependencies

- P1 → P2 (screens use the kit + merged face). P2 → P3 (rotation drives the
  world the screens render). P4 last (tests assert the final UI). P1's face merge
  is independent of the rest and lowest-risk → first.

## Hard contracts to preserve (do NOT regress)

From shipped red-team work (`HANDOFF-SPEC.md` §8):

1. Picker load states loading / error / loaded MUST stay distinct (a fetch error
   never looks like an empty list).
2. Double-tap guards on picker-pick, add-child, talk button, mode chips.
3. Voice back runs `shutdown()` (→ `_leave()`) BEFORE pop so the backend
   summarizes; `PopScope(canPop:false)` intercept stays.
4. Talk button locked during `connecting` (cold-start) and `disconnected`.
5. Gender required (boy/girl) in the form; neutral is guest-display only; the
   form never persists neutral (`toProfileJson` throws on neutral).
6. Guest session persists nothing (no deviceId → `?profile=guest`).
7. 5-child soft cap + the 409 "đã đủ 5 bé" message; server-validation surfaces.
8. Mode chips = `LearningMode.values`; switching reconnects (the controller does
   this); the active chip stays highlighted via the controller listener.
9. Dev transcript toggle (long-press the voice title) stays reachable.
10. The robot screen stays dark in every world (LED face always legible).

## Resolved design decisions

1. **Face merge, not replace.** Add `bloom` (default 1.0) + the richer paint loop
   (glass sheen, core highlight, 2-pass bloom) from `preview/lib/shared/robot_face.dart`
   INTO `app/lib/robot_face.dart`. The two files are byte-identical except those
   additions, so existing callers (`_GlowingFace`, picker card, manage) are
   unaffected (bloom defaults to baseline). No new enum/variant.
2. **New files for the kit** (ported ~as-is, no logic): `app/lib/scene/flat_art_kit.dart`,
   `app/lib/scene/scene_spec.dart`, `app/lib/scene/scene_worlds.dart`. The preview's
   `scene_flow.dart` is NOT ported wholesale — its widgets (SceneBackdrop,
   SpeechBubble, StandingRobot) are extracted into `app/lib/scene/scene_widgets.dart`
   (reusable, data-agnostic), and the screen logic is rebuilt in the REAL screens
   with REAL controllers/services. (The preview's screens are mock-driven.)
3. **`FlatArt` palette is additive** — keep `app_theme.dart` `paletteFor()` for the
   gendered FACE/body tint (girl magenta / boy cyan via `FlatArt.tintFor`), but the
   screen background is now the per-world gradient, not `childBackground()`. The
   app theme switches to a light Baloo-2 theme (Material parent screens — manage,
   dialogs — inherit it; they stay Material, not flat-art).
4. **ThemeRotation** = a `ChangeNotifier` service persisted in `shared_preferences`
   (already a dep): `currentWorldId` + `randomPerSession`. Created once in
   `MonamiApp`, loaded before first frame (like `DeviceIdentity`), passed to the
   picker + voice screens. `onSessionEnd(dwell)` rotates iff random && dwell > 2min.
5. **Dwell timer** = the voice screen records `DateTime.now()` on init and, in
   `_leave()` (the single exit path), computes the dwell and calls
   `themeRotation.onSessionEnd(dwell)` BEFORE pop. The picker reads the (possibly
   rotated) world on its next build.
6. **Parent setting** = a gear in the picker top bar (grown-up area, consistent
   with the per-card gear) opening a small sheet: Fixed (pick a world) | Random
   per session. Not kid-facing.
7. **confetti dep** added to `app/pubspec.yaml` (`confetti: ^0.8.0`). Celebrate
   fires on the controller's existing `happyPulse` signal (same as preview).

## Acceptance (whole plan)

- App launches into the flat-art picker in the persisted world (default `night`),
  children standing as characters; loading/error/loaded states intact.
- Voice screen: robot stands in the world, speech bubble reflects state, mode
  chips = LearningMode, talk button uses real `toggleMic` and is locked during
  connecting/disconnected; back runs shutdown→pop; confetti on happy pulse.
- Form: scene-styled, real validation (name ≤20, gender required, 409 message),
  real create/update via ChildService.
- After a >2-min voice session, returning to the picker shows a DIFFERENT world
  (when Random); Fixed locks one world; choice persists across app restart.
- All 6 worlds render (CustomPainter, deterministic, no Random/DateTime in paint).
- `flutter analyze` clean; `flutter test` green (behavioral tests unchanged, render
  tests updated to the new UI).
- Every "Hard contract" above verified by a reviewer walk + a test where one exists.

## Out of scope

- Backend changes (none). Android. Real-device TestFlight build (separate
  user-gated step; build path in `app/RELEASE.md`).
- Restyling the parent-facing manage screen / memory dialog into flat-art (they
  inherit the new Material theme; kept Material by design).
- New worlds beyond the 6; per-world sound; animation beyond the spec.

## Risks (summary; per-phase detail in phase files)

- Widget-test regression (13 tests, several assert dark UI) → Phase 4 updates them;
  behavioral tests stay. Mitigated + explicit.
- Losing a red-team contract during restyle → each screen phase lists the exact
  contract lines to carry; reviewer walks all 10.
- Theme persistence race at launch → load ThemeRotation before `runApp` (proven
  pattern: `DeviceIdentity().ensure()` already does this).
- Performance (per-world painter + face + confetti) → keep RepaintBoundary + the
  shared 20s controller from the preview; painters stay deterministic.
