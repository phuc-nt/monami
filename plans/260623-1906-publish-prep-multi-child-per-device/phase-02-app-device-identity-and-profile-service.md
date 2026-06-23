---
phase: 2
title: "App Device Identity and Profile Service"
status: completed
priority: P1
effort: "1d"
dependencies: [1]
---

# Phase 2: App Device Identity and Profile Service

## Overview

Give the Flutter app a stable anonymous `deviceId` (Keychain-backed) and a thin
service client over the new backend REST, plus local caching. This is the seam
every app feature (3, 4, 5) builds on.

## Requirements

- Functional:
  - On first launch: generate a UUID `deviceId`, store in **iOS Keychain**
    (survives app delete). Cache in `shared_preferences` for fast reads; Keychain
    is source of truth.
  - `ChildService`: `listChildren()`, `createChild(name, gender, age, interests)`,
    `updateChild(id, …)`, `deleteChild(id)`, `getMemory(id)`/`setMemory(id, text)`/
    `clearMemory(id)` — all hitting the phase-1 REST with the shared token + deviceId.
  - `Child` model (id, name, gender, age, interests, memorySummary, updatedAt).
  - `VoiceController` connects with `?device=<deviceId>&profile=<childId>` (guest
    path added in phase 5).
  - Cache the child list locally so the picker renders instantly offline-ish, then
    refresh from REST.
- Non-functional:
  - **Neither `deviceId` nor the token is ever logged or crash-reported.** Today
    `voice_controller.dart` builds `_url` (with token) once and stores it as a
    field; phase 2 adds `?device=<uuid>` to it. Assemble the URI at connect-time and
    keep `_url`/token/deviceId out of any `print`/`toString`/`FlutterError.onError`/
    crash-reporter path. (Red-team finding 4d / backend finding 3.)
  - REST failures surface as **typed errors** the UI can show — a network/timeout
    error must be distinguishable from a real empty list (no "empty vs. error"
    confusion; phase 3 depends on this distinction).
  - Keep `AppConfig` the single source for base URL + token (extend, don't fork).

## Architecture

- Add deps: `flutter_secure_storage` (Keychain) + `shared_preferences` +
  `http` (or reuse an existing client). Pin versions in `pubspec.yaml`.
- New `device_identity.dart`: `DeviceIdentity.ensure()` → returns the persisted
  UUID (Keychain → prefs fallback).
- New `child_service.dart`: REST client wrapping the 6 endpoints; uses
  `AppConfig.restBase` (derive from `wsBase`) + token + deviceId.
- New `child_model.dart`: `Child` + JSON (de)serialization matching phase-1 schema.
- `app_config.dart`: add `restBase` (https sibling of `wsBase`); keep token.
- `voice_controller.dart`: thread `deviceId` into the WS URL builder.

## Related Code Files

- Create: `app/lib/device_identity.dart`, `app/lib/child_service.dart`,
  `app/lib/child_model.dart`.
- Modify: `app/lib/app_config.dart`, `app/lib/voice_controller.dart`,
  `app/pubspec.yaml`.
- Create (tests): `app/test/child_model_test.dart`,
  `app/test/device_identity_test.dart` (mock storage).

## Implementation Steps

1. Add `flutter_secure_storage`, `shared_preferences`, `http` to `pubspec.yaml`.
2. `device_identity.dart`: ensure/generate/persist UUID (Keychain primary, prefs cache + fallback).
3. `child_model.dart`: `Child` model + JSON round-trip, matching phase-1 contract exactly.
4. `child_service.dart`: typed methods over the 6 endpoints; inject token + deviceId; map non-2xx to typed errors.
5. `app_config.dart`: add `restBase` = **origin of `wsBase`** — replace scheme
   (`wss→https`, `ws→http`) AND strip the path to `/` (drop `/ws/voice`). Concrete:
   `wss://foo.run.app/ws/voice` → `https://foo.run.app`. `voice_controller.dart`:
   add `device` query param. (Red-team: naive scheme-swap leaves `/ws/voice` on REST
   calls → all CRUD hits the wrong endpoint.)
6. **Startup/reinstall ordering:** on launch, `DeviceIdentity.ensure()` (Keychain →
   prefs fallback). prefs cache is wiped on reinstall but Keychain `deviceId`
   persists → if cache is empty, treat the picker as **loading** (fetch from
   backend) and only show the empty state after a **successful empty** REST
   response — never on a cache-miss or a fetch error. (Prevents the "reinstall shows
   no children → parent re-creates duplicates" trap.)
7. Tests: model JSON round-trip; identity persistence/fallback with a mock store;
   **`restBase` derivation unit test** (required, not optional):
   `wss://foo.run.app/ws/voice` → `https://foo.run.app`,
   `ws://127.0.0.1:8000/ws/voice` → `http://127.0.0.1:8000`.
8. Manual: point app at local backend (phase 1), create a child via service from a scratch screen/log, confirm Firestore/JSON doc appears under the device path.

## Success Criteria

- [ ] Fresh install generates + persists a `deviceId`; reinstall (Keychain kept) returns the same id.
- [ ] After reinstall (prefs empty, Keychain present), the app **fetches before** showing empty state — never flashes "no children" on a cache miss.
- [ ] `ChildService` round-trips all 6 operations against the local backend.
- [ ] `Child` JSON matches the backend schema (no field drift); tests green.
- [ ] `restBase` derivation test passes (`…/ws/voice` stripped to origin).
- [ ] WS connects with `?device=&profile=` and the existing voice loop still works.
- [ ] Neither `deviceId` nor token appears in any log/crash output.

## Risk Assessment

- **Keychain on simulator vs. device** can differ — test the fallback path; don't
  assume Keychain is always available.
- **restBase derivation** from `wsBase` must handle `ws→http`/`wss→https` + path
  swap (`/ws/voice` → ``) cleanly; cover with a tiny unit check.
- **Contract drift** with phase 1 — model tests pin the JSON shape; if phase 1
  changes a field name, this test fails fast.
- **Rollback:** new files + additive config; the existing hardcoded picker still
  works until phase 3 swaps it.
