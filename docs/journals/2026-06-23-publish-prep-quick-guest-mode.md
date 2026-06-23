# Publish-prep phase 5: quick guest mode

**Date:** 2026-06-23
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (phase 5 of 6)

## Goal

"Khách (chơi nhanh)" → a no-setup, no-storage voice session: neutral UI,
`profile=guest`, no `deviceId`, backend persists nothing. Most of the wiring
already existed from phases 3–4; phase 5 locked in the no-persist invariant and
added the tests.

## What was already wired (phases 3–4)

Picker "Khách" → `onGuest` → `VoiceHome.guest()` (child=null, deviceId='',
profileId='guest', neutral face/palette) → `VoiceController` builds a guest URL.
The backend `is_guest` gate (phase 1) already short-circuits persistence.

## What phase 5 added

- **Pure URL builder.** Extracted the WS URL logic from `VoiceController` into a
  top-level `buildConnectUrl(base, {profileId, token, deviceId})` that drops empty
  values — so a guest (empty deviceId) connects with `?profile=guest` and **no**
  `device`, which is exactly what makes the backend write nothing. The instance
  `_buildUrl()` delegates to it (DRY). Pure → unit-testable without constructing a
  `VoiceController` (which instantiates `AudioRecorder`, needing platform plugins).
- **App test** `guest_mode_url_test.dart` — guest URL omits device + uses
  `profile=guest`; a registered child includes device+child; empty token/device
  dropped; stable append order (device, profile, token).
- **Backend test** `test_guest_session_no_persist.py` — drives the real
  `run_session` with a mocked Gemini client + a fake session that yields one
  transcript turn, asserting the `persist` gate from BOTH sides: guest /
  old-build-no-device / unknown-child write **nothing**, while a registered child
  with a non-empty transcript **does** call `save_memory(device, child, summary)`.

## Verification

- 38/38 app tests, 24/24 backend tests, `flutter analyze` clean.
- **Simulator E2E (iPhone 17 Pro vs live backend):** tapped "Khách" → guest voice
  screen with the **neutral** face; after the session the backend device had
  **zero children** and the store dir had **no data written at all**; the backend
  logged `client connected … (guest=True)`. No leak into real data.

## Review

Verdict: safe, all 4 criteria MET, guest no-persist invariant correct +
mutation-proven. Review fixes landed before finalize:
- **H1** — the backend fake session originally lacked `receive()`, so the test
  passed via a swallowed `AttributeError` rather than the documented downlink path.
  Rebuilt the fake to yield a real transcript turn + added the positive
  (registered-child-persists) case.
- **M1/M2** — removed a tautological "controller uses the same builder" test and
  the now-dead `debugConnectUrl()` (the `=>` delegation is compiler-guaranteed);
  replaced with an append-order assertion.

## State

Phase 5 complete + reviewed. Only **phase 6 (TestFlight + pre-publish polish)**
remains. Parental PIN + time-limit still deferred to a later phase.
