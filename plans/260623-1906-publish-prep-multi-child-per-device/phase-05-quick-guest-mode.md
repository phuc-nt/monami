---
phase: 5
title: "Quick Guest Mode"
status: pending
priority: P2
effort: "0.5d"
dependencies: [3]
---

# Phase 5: Quick Guest Mode

## Overview

Wire the "Khách (quick mode)" entry to a no-setup, no-storage voice session:
neutral UI, `profile=guest`, no `deviceId` sent, backend persists nothing.

## Requirements

- Functional:
  - Tap "Khách" → straight into a voice session with a neutral default profile
    (no name, neutral face variant, neutral palette).
  - WS connects with `?profile=guest` and **omits** `device` (or a sentinel the
    backend treats as guest); backend (phase 1) loads/saves **no memory**.
  - No child doc created; nothing written to Firestore; session forgotten on exit.
  - Back from a guest session returns to the picker, no residue.
- Non-functional:
  - Reuse the existing voice screen + controller; guest is just a profile/route
    variant, not a parallel code path.
  - Neutral default profile text (age-appropriate bilingual companion) lives
    server-side (phase 1 guest/default profile).

## Architecture

- `profile_picker.dart`: "Khách" action → `VoiceHome` with a `guest` sentinel
  child (id `guest`, **neutral** face variant per phase 4, no deviceId).
- `voice_controller.dart`: when child is guest, build the WS URL **without** `device`
  and with `profile=guest`.
- Backend (phase 1) short-circuits persistence via the **`is_guest` computed from
  raw params before `get_profile()`** — re-confirm here that the
  `DEFAULT_PROFILE_ID="vy"` fallback does **not** cause a guest session to write to
  `vy`'s memory. This is the one invariant phase 5 lives or dies on.

## Related Code Files

- Modify: `app/lib/profile_picker.dart`, `app/lib/main.dart` (guest route),
  `app/lib/voice_controller.dart` (guest URL).
- Verify: backend guest no-persist branch from phase 1.
- Create (tests): `app/test/guest_mode_url_test.dart` (URL omits device, profile=guest).

## Implementation Steps

1. Define a `guest` sentinel `Child` (neutral variant/palette) the picker routes to.
2. `voice_controller.dart`: guest → WS URL without `device`, `profile=guest`.
3. Confirm backend persists nothing for guest (phase-1 branch) via a session + Firestore check.
4. Test: guest URL builder; manual guest session leaves zero Firestore writes.

## Success Criteria

- [ ] "Khách" starts a full voice session with neutral UI + face.
- [ ] No `device` sent; `profile=guest`; backend writes nothing (verified in Firestore — no new device/child doc, no memory).
- [ ] Exiting guest leaves no residue; returns cleanly to picker.
- [ ] Voice loop quality identical to a normal session (minus memory).

## Risk Assessment

- **Accidental persistence** — explicitly assert "no Firestore write" in manual
  verification; the no-persist branch is the one thing that must hold.
- **Code duplication** — guest must reuse the voice screen/controller, not a fork;
  only the URL + profile differ.
- **Rollback:** guest is a thin add; removing the picker entry disables it with no
  effect on registered-child flows.
