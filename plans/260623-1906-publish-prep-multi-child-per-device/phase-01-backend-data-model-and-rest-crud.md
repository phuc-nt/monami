---
phase: 1
title: "Backend Data Model and REST CRUD"
status: completed
priority: P1
effort: "1.5d"
dependencies: []
---

# Phase 1: Backend Data Model and REST CRUD

## Overview

Reshape backend storage from flat `child_memory/{id}` to per-device
`devices/{deviceId}/children/{childId}`, add `gender` to the profile, and expose
REST CRUD (children + memory edit/clear) on the existing FastAPI app behind the
existing shared token. WS voice routing gains a `device` param.

## Requirements

- Functional:
  - Firestore: `devices/{deviceId}/children/{childId}` doc holding
    `profile{name, gender, age, interests[], createdAt}` + `memory{summary, updatedAt}`.
  - REST (all gated by the existing shared token, same as WS):
    - `GET /devices/{deviceId}/children` → list child profiles (+ memory summary).
    - `POST /devices/{deviceId}/children` → create (name, gender, age, interests). Server assigns `childId` (UUID) + `createdAt`. Reject if device already has 5 (soft cap).
    - `PATCH /devices/{deviceId}/children/{childId}` → update profile fields.
    - `DELETE /devices/{deviceId}/children/{childId}` → delete child + its memory.
    - `PATCH /devices/{deviceId}/children/{childId}/memory` → replace memory summary text.
    - `DELETE /devices/{deviceId}/children/{childId}/memory` → clear memory (keep profile).
  - WS `/ws/voice?device=<deviceId>&profile=<childId>&token=<t>`: load/save memory under the device-scoped path. Profile text (name/age/interests/gender) for the Gemini system prompt comes from the child doc, not the hardcoded registry.
  - **Guest / no-device (CRITICAL invariant — persist NOTHING):** compute
    `is_guest = (not raw_device) or (raw_profile == "guest")` from the **raw** query
    params **before** any `get_profile()` resolution; thread `is_guest` into
    `run_session`; gate BOTH `load_memory` and `_update_memory` on `not is_guest`.
    **Do not** check guest-ness against the resolved `profile.profile_id` — today
    `get_profile("guest")` falls back to `DEFAULT_PROFILE_ID="vy"`, so a post-resolution
    `child_id == "guest"` check is never true and the disconnect summarizer would
    write to `child_memory/vy`. (Red-team finding 1.)
  - **Cutover compat shim:** an old client sending `?profile=vy` with **no** `device`
    must hit the guest path (no crash, no memory write), not a 500. Deploy the new
    backend only after the old on-device build is retired; the old flat
    `child_memory/{vy,phong}` docs are intentionally abandoned (not migrated, not read).
- Non-functional:
  - Same shared-token gate; `secrets.compare_digest`. No new secrets.
  - `deviceId`/`childId` path-sanitized (alnum + dash + underscore) as today.
  - Firestore errors caught (session/REST must not 500 the voice loop); REST returns clean 4xx/5xx JSON.
  - Keep `/health` and the WS binary/JSON message protocol **unchanged**.
  - **Memory writes never use a full `.set()`** — use `set(merge=True)` or
    `update({"memory.summary":…, "memory.updatedAt":…})` on the `memory.*` sub-keys
    only, so a concurrent profile `PATCH` (or vice-versa) can't clobber the other's
    fields (memory is merged into the child doc). (Red-team finding 4.)
  - **`deviceId` out of info-level logs.** `gemini_session.py` currently logs
    `profile=%s`; the new equivalent must NOT log the raw deviceId at info level
    (redact or debug-only). It's a bearer capability — a leaked log line = another
    tester's data. (Red-team finding 3.)
  - **Validation (Pydantic, reject bad input with 422, don't silently accept):**
    `gender ∈ {boy, girl}` (enum); `age` bounded (e.g. 1–12); `name` 1–20 chars,
    unicode/diacritics preserved (VN names); `interests` capped (e.g. ≤10 items,
    each ≤30 chars). `childId` is **server-generated** UUID on POST (client cannot
    supply it). (Red-team finding 6.)
  - **Explicit REST contract:** `PATCH` is partial-merge (unset fields untouched);
    `GET` on a device with no children → `200 []`; `DELETE` is idempotent → `204`
    whether or not the child existed; bad/missing token → `401`; over-cap POST →
    `409` with a clear message. Document these in the router.

## Architecture

- `profile_store.py`: change signatures to `load_memory(device_id, child_id)` /
  `save_memory(device_id, child_id, summary, updated_at)`; add child-doc CRUD
  helpers (`list_children`, `create_child`, `get_child`, `update_child`,
  `delete_child`). Firestore path builder `devices/{d}/children/{c}`. JSON local
  backend mirrors with `profiles/devices/{d}/children/{c}.json` (or a nested dict
  file) so local dev still works without Firestore.
- New `child_profile.py` role: it stops being a hardcoded registry. Keep a
  `ChildProfile` dataclass + a `guest`/default profile constant; resolve a child's
  profile from the store by `(device_id, child_id)`. The Gemini system-prompt
  builder consumes a `ChildProfile` regardless of source.
- New module `child_rest_api.py` (FastAPI `APIRouter`) holding the 6 endpoints +
  token dependency; mounted in `main.py`. Keeps `main.py` lean (<200 LOC rule).
- `gemini_session.py`: `run_session` takes `(ws, device_id, child_id)`; resolves
  the profile from the store; `load_memory`/`_update_memory` use the device-scoped
  keys; guest/no-device → skip both.
- `main.py`: WS handler reads `device` + `profile` query params; mounts the REST
  router; token check shared by WS + REST.

## Related Code Files

- Create: `backend/child_rest_api.py` (REST router), `backend/child_store.py` *(optional split if `profile_store.py` exceeds ~200 LOC — child CRUD vs. memory load/save)*.
- Modify: `backend/profile_store.py`, `backend/child_profile.py`,
  `backend/gemini_session.py`, `backend/main.py`,
  `backend/gemini_session_config.py` (system prompt now includes gender),
  `backend/.env.example` (note device-scoped paths if any new env).
- Create (tests): `backend/tests/test_child_rest_api.py`,
  `backend/tests/test_profile_store_device_scoped.py`.
- Delete: none (hardcoded vy/phong constants removed from `child_profile.py`, file stays).

## Implementation Steps

1. Add `gender` to `ChildProfile` + a `guest`/default profile; drop hardcoded vy/phong.
2. Rewrite `profile_store.py` to device-scoped keys + child-doc CRUD helpers; keep JSON + Firestore backends. Path-sanitize both ids.
3. Build `child_rest_api.py` router with the 6 endpoints, Pydantic request/response models, shared token dependency, soft-cap-5 check on create.
4. Mount the router in `main.py`; share the token check; add `device` param to the WS handler; pass `(device_id, child_id)` into `run_session`.
5. Update `gemini_session.py` to resolve profile from store + device-scoped memory; guest/no-device → no persistence.
6. Update `gemini_session_config.py` system prompt to use gender (e.g. pronoun/voice tone hint) — keep bilingual + safety unchanged.
7. Write tests: REST CRUD happy-path + soft cap + isolation (two devices, same child name → separate docs) + memory edit/clear; store unit tests for path scoping.
8. Manual: run `uvicorn` locally with JSON backend; curl the 6 endpoints; run `scripts/ws_test_client.py` with `?device=…&profile=…` and confirm memory persists under the device path.

## Success Criteria

- [ ] 6 REST endpoints work locally (curl) behind the token; bad/missing token → 401.
- [ ] Two devices creating a child named "Bo" produce two isolated docs; neither sees the other's memory.
- [ ] Memory edit replaces text; memory clear empties summary but keeps the profile + child.
- [ ] Soft cap: 6th create on a device is rejected (409) with a clear message.
- [ ] WS voice with `?device=&profile=` loads/saves memory under the device path.
- [ ] **Guest invariant test:** a guest session that produces ≥2 transcript turns writes **ZERO** Firestore docs — assert no new device doc AND `child_memory/vy`/`devices/.../vy` is untouched (the `DEFAULT_PROFILE_ID="vy"` fallback does not leak).
- [ ] **Cutover shim:** an old-style `?profile=vy` (no `device`) connects + runs as guest (no crash, no memory write).
- [ ] **Concurrent-write test:** a profile `PATCH` and a memory `update` on the same child don't clobber each other (both fields survive) — proves `merge=True`/`update()`.
- [ ] **Validation:** invalid `gender`/`age`/oversized `interests`/`name` rejected with 422; VN diacritics round-trip intact.
- [ ] `deviceId` appears in no info-level log line.
- [ ] `/health` + WS message protocol unchanged; existing `ws_test_client.py` still drives a session.
- [ ] New backend tests pass; no 500 on Firestore-disabled fallback.

## Risk Assessment

- **Contract spread** across 4 backend modules — mitigate by landing the store
  signature change first with its unit tests, then layering REST + WS on top.
- **Local JSON backend parity** — ensure device-scoped JSON paths are sanitized to
  avoid traversal; cover with a unit test.
- **Guest seam** half-built here, finished in phase 5 — keep it as a single branch
  (`if not device_id or child_id == "guest": no-persist`) so phase 5 only adds UI.
- **Rollback:** backend is independently deployable; if REST misbehaves, the WS
  voice path is unaffected as long as routing params + storage keys are correct.
