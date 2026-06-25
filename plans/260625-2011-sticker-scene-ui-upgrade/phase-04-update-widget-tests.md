---
phase: 4
title: "Update widget tests to the new UI"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: [3]
---

# Phase 4: Update widget tests to the new UI

## Overview

Bring the test suite green against the new UI. Behavioral tests stay unchanged;
render/state widget tests are rewritten to assert the new flat-art screens while
still proving the SAME behaviors (states, locks, validation, guards).

## Requirements

- Run `cd app && flutter test` first to see exactly which of the 13 tests fail;
  fix only those. Keep UNCHANGED (no UI coupling): `device_identity_test`,
  `child_service_test`, `learning_mode_test`, `app_config_rest_base_test`,
  `guest_mode_url_test`, `echo_gate_test`, `child_model_test`.
- Update render/state tests to the new UI (assert behavior, not pixel styling):
  - `profile_picker_render_test.dart` — loading shows a spinner+label; error shows
    the retry affordance and is NOT the empty-loaded view; loaded shows a character
    per child + add affordance (≤5) + guest entry. Assert the THREE states stay
    distinct (the red-team invariant), not exact widgets.
  - `voice_screen_states_render_test.dart` — for connecting/idle/listening/speaking/
    disconnected: the talk control is locked on connecting+disconnected and enabled
    otherwise; the bubble/status reflects the state; back triggers shutdown. Assert
    the lock + state mapping, not the flat-art chrome.
  - `child_form_render_test.dart` — name required, gender required (no neutral),
    age slider, interests, 409 path. Assert validation behavior.
  - `robot_face_render_test.dart` — face builds for each variant + with/without
    `bloom`; no exception. Loosen any pixel-pinned assertion to "builds + paints".
  - `app_icon_render_test.dart`, `widget_test.dart` — adjust if they pin the old
    theme/screens; keep their intent.
- Add `theme_rotation_test.dart` (NEW): with an in-memory SharedPreferences,
  assert: default world `night`; `onSessionEnd(<2min)` no-op; `onSessionEnd(>2min,
  random)` changes to a different id; fixed mode never changes; `_pickDifferent`
  never returns current; persistence round-trips (load after set).

## Architecture

No production code changes here (unless a test surfaces a real bug → fix it and
note it). Tests assert BEHAVIOR + the preserved contracts, decoupled from styling
so a future restyle doesn't re-break them.

## Related Code Files

- Modify: the render/state tests listed above.
- Create: `app/test/theme_rotation_test.dart`.
- Keep unchanged: the behavioral tests listed above.

## Implementation Steps

1. `flutter test` → capture failures.
2. Rewrite each failing render/state test to assert behavior on the new widgets.
3. Add `theme_rotation_test.dart`.
4. `flutter test` green; `flutter analyze` clean.

## Success Criteria

- [ ] `flutter test` 100% green (all updated + unchanged + new).
- [ ] Picker test proves loading/error/loaded stay distinct.
- [ ] Voice test proves the talk lock on connecting/disconnected + state→bubble.
- [ ] Form test proves name/gender/age validation + 409.
- [ ] ThemeRotation test proves rotate>2min / no-op<2min / fixed / ≠current /
  persistence.
- [ ] `flutter analyze` clean.

## Risk Assessment

- **Tests pinned to exact widgets/pixels** → assert behavior + key affordances, not
  chrome, so they survive styling.
- **A test reveals a real regression** → fix the production code (don't weaken the
  test); surface via the no-side-effects gate.
- **Rollback:** test-only changes; revert restores the old assertions (which match
  the old UI).
