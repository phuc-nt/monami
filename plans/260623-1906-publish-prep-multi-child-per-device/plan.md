---
title: "Publish Prep: Multi-Child Per Device + TestFlight"
description: "Turn monami from 2 hardcoded children into an anonymous per-device multi-child app: Firestore devices/{deviceId}/children/{childId}, backend REST CRUD + memory edit/clear, app profile-management UI, two gendered robot-face variants, quick/guest mode, then a real TestFlight build. Touches the data model + public WS/REST contracts."
status: pending
priority: P1
created: 2026-06-23
blockedBy: [260622-2119-two-profiles-and-memory, 260622-2337-deploy-cloud-run]
---

# Publish Prep: Multi-Child Per Device + TestFlight

## Overview

monami today ships 2 **hardcoded** children (vy/phong) with memory in a flat
`child_memory/{id}` namespace, a WS-only backend, and zero local persistence.
This phase makes it a real multi-child app — anonymous **per device** — so a
parent can register/edit several children and edit/clear each child's memory,
gives boys/girls distinct robot faces, adds a no-storage guest mode, and ships
the result to TestFlight for real testers.

Foundation design + decisions are locked in the approved brainstorm:
`plans/reports/brainstorm-260623-1906-multi-child-per-device-publish-prep-report.md`.

## Decided (from brainstorm)

- **Anonymous per-device** model (not real accounts). `deviceId` = UUID in iOS
  Keychain; app self-declares it. Shared token stays the gate.
- **Firestore:** `devices/{deviceId}/children/{childId}`; child doc holds
  `profile{name,gender,age,interests[],createdAt}` + `memory{summary,updatedAt}`
  merged. Old vy/phong test data **not migrated**.
- **Backend gains REST CRUD** (same FastAPI app, same token) for children + memory
  edit/clear. WS adds `?device=<uuid>`.
- **Gendered UI:** two distinct robot-face variants + palettes (the long pole).
- **Quick/guest mode:** `profile=guest`, no deviceId, persists nothing.
- **Interests:** preset chips + free-add. **Soft cap 5** children/device.
- **Out of scope (deferred):** parental PIN + time-limit, real accounts, Android,
  per-device JWT, offline mode.
- **TestFlight ready:** paid Apple Developer Program + App Store Connect under team
  `75EN938B6L`.

## Phases

| Phase | Name | Status | Depends on |
|-------|------|--------|-----------|
| 1 | [Backend Data Model and REST CRUD](./phase-01-backend-data-model-and-rest-crud.md) | ✅ completed | — |
| 2 | [App Device Identity and Profile Service](./phase-02-app-device-identity-and-profile-service.md) | ✅ completed | 1 |
| 3 | [App Profile Management UI](./phase-03-app-profile-management-ui.md) | ✅ completed | 2 |
| 4 | [Gendered Robot Face](./phase-04-gendered-robot-face.md) | ✅ completed | 3 |
| 5 | [Quick Guest Mode](./phase-05-quick-guest-mode.md) | ✅ completed | 3 |
| 6 | [TestFlight Release and Pre-Publish Polish](./phase-06-testflight-release-and-pre-publish-polish.md) | pending | 1-5 |

**Ordering (strictly serial 1→2→3→4→5→6).** Red-team correction: phases 3, 4, 5 are
**NOT** parallel — they all edit `profile_picker.dart` and `main.dart` (3 reworks
the picker + routes; 4 threads the face variant through picker + voice screen; 5
adds the guest action + route). Parallel editing = merge conflicts for a solo dev.
So: 1 (backend contract) first; 2 (identity + service) unblocks app work; 3
(picker + CRUD screens) establishes the picker/route structure; 4 (gendered face)
and 5 (guest) layer onto that structure one at a time; 6 last (full feature set +
real-device pass before TestFlight). Only `robot_face.dart` is truly isolated.

## Acceptance criteria (whole plan)

- One device creates ≥2 children; each has **isolated** memory; deleting one
  child leaves the other's profile + memory intact.
- Parent can edit a child's profile and **edit or clear** that child's memory from
  the app; changes reflected in Firestore.
- Boy vs. girl renders the correct robot-face variant + palette end to end.
- Guest mode runs a full voice session and persists **nothing** (no Firestore
  write, no device doc).
- App reinstall keeps the same `deviceId` (Keychain) → children still listed.
- WS voice loop + per-child memory recall still work (no regression) using the new
  `?device=&profile=` routing.
- A real build is uploaded to TestFlight and installs on a tester's device.

## Scope OUT

Parental PIN + time-limit; real email/Apple accounts; Android; per-device JWT;
offline mode; migrating the old vy/phong data.

## Risks (plan-level) — red-team hardened

- **Guest persistence leak (CRITICAL, code-proven).** `get_profile("guest")` falls
  back to `DEFAULT_PROFILE_ID="vy"` (`child_profile.py`), so the disconnect
  summarizer in `gemini_session.py`'s `finally` would write to `child_memory/vy`.
  The guest check MUST be computed from the **raw** WS params *before*
  `get_profile()` and carried as an `is_guest` flag gating both `load_memory` and
  `_update_memory`. Never check guest-ness against the resolved `profile.profile_id`.
  (Phase 1 + 5.)
- **Firestore clobber race (HIGH).** Memory is merged into the child doc; a profile
  `PATCH` and a session-end memory save with full `.set()` = last-write-wins data
  loss. Memory writes MUST use `set(merge=True)` / `update()` on `memory.*` only.
  (Phase 1.)
- **Hard-cutover footgun (HIGH).** The deployed backend + the dev's old on-device
  build use `?profile=vy`. New backend expects `?device=&profile=`. Add a
  `device=None` → guest (no-persist, no-crash) compat shim; deploy new backend only
  after retiring the old build; old `child_memory/{vy,phong}` docs are
  intentionally abandoned. (Phase 1.)
- **Contract change** (`profile_id` → `deviceId,childId`) spans
  `main.py`/`gemini_session.py`/`profile_store.py`/`memory_summarizer.py`.
  Mitigation: phase 1 keeps `/health` + the WS message protocol unchanged; only
  routing params + storage keys change.
- **Two robot faces** = biggest schedule risk (subjective art, monolithic painter
  refactor). Neutral/guest face = the **current single face + gray palette** (zero
  new art) — decided, not left to the implementer. If the variants slip the
  timebox, **surface to the user** (don't silently revert to color-only — that
  reverses the brainstorm decision). (Phase 4.)
- **New local persistence** (Keychain + shared_preferences). `deviceId` AND the
  token must stay out of logs/crash reports; on reinstall, prefs are wiped but
  Keychain persists, so the app must fetch before showing an empty state. (Phase 2.)
- **TestFlight + kids-app review (CRITICAL for store).** Internal testers only (no
  external group / no Beta App Review); a **privacy policy URL** is required;
  nutrition labels must declare **audio transmitted to Google Vertex AI** (not just
  "no audio stored"); age rating **4+ with privacy policy, NOT Kids Category**.
  (Phase 6.)

## Dependencies

- Builds on completed plans `260622-2119-two-profiles-and-memory` (the memory +
  profile substrate this generalizes) and `260622-2337-deploy-cloud-run` (the live
  Cloud Run + Firestore + Secret Manager backend this extends).
