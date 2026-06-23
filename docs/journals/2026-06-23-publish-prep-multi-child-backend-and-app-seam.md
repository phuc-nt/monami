# Publish-prep: multi-child backend + app identity/service seam

**Date:** 2026-06-23
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (phases 1–2 of 6)
**Brainstorm:** `plans/reports/brainstorm-260623-1906-multi-child-per-device-publish-prep-report.md`
**Red-team:** `plans/260623-1906-publish-prep-multi-child-per-device/reports/`

## Goal

Turn monami from 2 hardcoded children into anonymous **per-device** multi-child,
ahead of a TestFlight build. Model: `devices/{deviceId}/children/{childId}` with
profile + memory merged in one doc; deviceId = app-generated UUID in iOS Keychain;
shared token still the gate. Decided via brainstorm, hardened by a 2-reviewer
red-team (10 findings folded into the plan before coding).

## Phase 1 — backend (done)

- New `child_store.py`: device-scoped CRUD + merged `memory{summary,updated_at}`;
  JSON (local) + Firestore backends; memory writes use `set(merge=True)` so a
  profile PATCH and a session-end memory save never clobber each other.
- New `child_rest_api.py`: 6 REST endpoints (list/create/update/delete +
  memory edit/clear) on the existing FastAPI app, same shared token; Pydantic
  validation (gender boy|girl, age 1–12, name ≤20, interests ≤10), soft-cap 5
  (409), server-generated childId, id-format guard (422, no path aliasing).
- Rewrote `child_profile.py`: dropped hardcoded vy/phong + `get_profile`/
  `DEFAULT_PROFILE_ID`; added `gender`, `GUEST_PROFILE`, `profile_from_record`.
- `gemini_session.run_session(ws, device_id, child_id, is_guest)`: guest/unknown
  → GUEST_PROFILE + **no persistence**. Deleted `profile_store.py`.
- `main.py`: mounts the router; WS reads `device`+`profile`; computes `is_guest`
  from RAW params before resolution; old `?profile=vy` (no device) lands as guest
  (cutover shim, no crash).

**The critical fix (red-team #1, code-proven):** `get_profile("guest")` used to
fall back to `DEFAULT_PROFILE_ID="vy"`, so a guest's end-of-session summarizer
wrote into Vy's real memory. Guest-ness is now computed from raw params and gates
both load + save; defense-in-depth no-op in the store too.

**Review fixes:** Firestore `save_memory` on a missing child now no-ops (was an
upsert ghost-doc, diverging from JSON); id-format rejected at the boundary.

20/20 backend pytest; curl smoke verified full lifecycle + zero leak into real data.

## Phase 2 — app identity + service seam (done)

- `device_identity.dart`: `ensure()` → persistent UUID, Keychain primary +
  shared_preferences cache/fallback; never logged. Reinstall keeps the id
  (Keychain), so on a prefs cache-miss the app must fetch before showing empty.
- `child_service.dart`: typed REST client over the 6 endpoints; typed
  `ChildServiceException` distinct from a real empty list; raw errors (which can
  carry URL+token) masked; `utf8.decode` for VN diacritics.
- `child_model.dart`: `Child` + `ChildGender{boy,girl,neutral}`, JSON matching the
  backend; `toProfileJson` **throws on neutral** (registered children are always
  boy/girl; neutral is display/guest-only — backend rejects it).
- `app_config.dart`: `restBase` = origin of `wsBase` (ws→http, wss→https, path
  stripped) with a required unit test.
- `voice_controller.dart`: takes `deviceId`, adds `?device=`; URL assembled at
  connect-time (no stored `_url` field) so token+deviceId never sit on the
  instance for a crash reporter to capture.

28/28 app unit tests + `flutter analyze` clean. **Simulator E2E** (iPhone 17 Pro
vs live local backend): real deviceId persisted, full CRUD+memory lifecycle over
real HTTP, cross-device isolation — and the backend created
`devices/{uuid}/children/` exactly as designed, no leak into real data.

## Decisions / carry-forward

- **neutral gender** is app-display + guest only; never POST/PATCH it (confirmed
  with user). Registered-child create form requires boy/girl (phase 3).
- **Phase 3 must** `WidgetsFlutterBinding.ensureInitialized()` before
  `DeviceIdentity().ensure()`, resolve deviceId once at startup, pass into
  `VoiceHome(deviceId:)`, and map a 409 to a distinct "đủ 5 bé" message. (Folded
  into the phase-3 plan.)
- Token still travels as a query param (consistent with the WS); a later phase may
  move it to a header (kids-app/TestFlight hardening).

## State

Phases 1–2 complete + reviewed. Next: phase 3 (profile-management UI) → 4 gendered
face → 5 guest mode → 6 TestFlight. Parental PIN + time-limit deferred to a later
phase.
