# Brainstorm: Multi-child per device + publish-prep

**Date:** 2026-06-23
**Status:** Design approved → proceed to plan
**Scope:** Foundation design for the publish-prep phase, focused on "1 device → nhiều bé"

## Problem statement

monami today: 2 children **hardcoded** (vy/phong) in both app + backend; memory keyed by `child_id` only in a **flat global namespace** (`child_memory/{id}`); no device/account layer; app fully stateless (no local persistence); backend is **WS-voice-only** (no profile CRUD). User wants, before TestFlight:

- multiple users (decided: **anonymous per-device**),
- one device registers + edits **multiple** children,
- edit + clear the memory the app keeps per child,
- gendered UI (male/female) — decided: **two distinct robot-face variants**,
- quick/guest mode (no profile, no long-term storage),
- publish to TestFlight + necessary pre-publish polish.

This report locks the **data model + identity + auth + API + UX** for the multi-child foundation. Everything else in the phase hangs off it.

## Core risk addressed

Flat `child_id` keying = **cross-device memory collision** (two devices both name a child "Bo" → shared memory). Fix: scope every child under its device so the storage path is globally unique by construction.

## Decisions (locked via Q&A)

| Decision | Choice | Rejected alternatives |
|---|---|---|
| **Multi-user meaning** | Anonymous **per-device** | Real accounts (email/Apple) — too heavy, slows TestFlight; flat "just add children" — keeps collision risk |
| **Firestore model** | Nested subcollection `devices/{deviceId}/children/{childId}` | Flat + `deviceId` field (leak-prone, must always filter); single doc with `children[]` array (1 MB cap, hot doc, hard per-child locking) |
| **Memory location** | **Merged into the child doc** (`{summary, updatedAt}`) | Separate memory subcollection — overkill for one small text |
| **deviceId source** | UUID generated in-app, stored in **iOS Keychain** | shared_preferences (lost on app delete); IDFV (changes on full vendor-app delete) |
| **Device auth** | Existing **shared token** + app **self-declares** `?device=<uuid>` | Per-device JWT — deferred; unnecessary for friends/family test |
| **Quick mode** | Guest session: `profile=guest`, no deviceId, backend persists nothing | Ask name+gender but don't save; in-session-only memory |
| **Gendered UI** | **Two distinct robot-face variants** + palettes by `gender` | Color/accent only; parent-picked theme |
| **Phase scope** | Do everything, then publish (single phase) | Two waves (core → polish) |
| **Old test data** | **Not migrated** (user's own throwaway test data) | One-time migration script (YAGNI) |

## Target design

### Firestore
```
devices/{deviceId}/
  children/{childId}
    profile: { name, gender, age, interests[], createdAt }
    memory:  { summary, updatedAt }
```
Path globally unique → no cross-device collision. `childId` = local UUID (uniqueness already guaranteed by the device path).

### Identity
- `deviceId` = UUID, generated first launch, persisted in **Keychain** (survives app delete; may iCloud-sync across the user's devices). App caches `deviceId` + child list in **shared_preferences** (the app's first local persistence). Firestore via REST stays source of truth.

### Wire protocol (minimal change)
```
wss://…/ws/voice?device=<uuid>&profile=<childId>&token=<shared>
```
Backend `load_memory(deviceId, childId)` / `save_memory(deviceId, childId, …)`. Token still gates strangers; deviceId is self-declared (sufficient for the test cohort).

### New backend REST (same FastAPI app, same shared token)
| Method | Path | Purpose |
|---|---|---|
| GET | `/devices/{deviceId}/children` | list |
| POST | `/devices/{deviceId}/children` | create (name, gender, age, interests) |
| PATCH | `/devices/{deviceId}/children/{childId}` | edit profile |
| DELETE | `/devices/{deviceId}/children/{childId}` | delete child (+ its memory) |
| PATCH | `/devices/{deviceId}/children/{childId}/memory` | edit memory text |
| DELETE | `/devices/{deviceId}/children/{childId}/memory` | clear memory (keep profile) |

### App UX
- Picker → load children from REST; add **"+ Thêm bé"** + **"Khách (quick mode)"**.
- Create/edit child form: name, **gender (nam/nữ)**, age, interests.
- Manage child: edit profile; **view / edit / clear memory**.
- Guest: neutral UI, no gender, no persistence.

### Gendered UI
`gender` → one of two robot-face variants (female: soft/decorative; male: strong) + matching palette. **Heaviest art + test cost** of the phase.

## Implementation considerations / risks

- **Backend signature change** (`profile_id` → `deviceId, childId`) touches `gemini_session.py`, `profile_store.py`, `main.py`. Keep `guest`/no-device path persisting nothing.
- **Firestore security rules:** backend uses an SA (server-side) so rules aren't the gate today; the shared token is. If rules are ever added for client access, the nested path makes per-device isolation trivial.
- **Two robot faces** = real design work; biggest schedule risk. Consider it the long pole.
- **Local persistence newly introduced** (shared_preferences + Keychain) — small but new surface; keep deviceId out of logs.
- **TestFlight**: needs ExportOptions/signing, App Store Connect app record, privacy nutrition labels (mic usage, no audio stored), review notes. Net-new, no existing CI/release config.
- **Parental PIN + time-limit** (prior remaining MVP item) folds into this phase per the "do everything" scope.

## Success criteria

- One device creates ≥2 children, each with isolated memory; deleting one doesn't touch the other.
- Edit child profile + edit/clear that child's memory from the app, reflected in Firestore.
- Gendered face renders correctly per child; guest mode persists nothing.
- App reinstall keeps the same deviceId (Keychain) → children still listed.
- Build distributed via TestFlight to real testers.

## Next steps

→ `/mk:plan` full publish-prep phase (this design as foundation): multi-child + CRUD + memory edit/clear + gendered face + quick mode + parental PIN/time-limit + TestFlight + pre-publish polish.

## Resolved (final)

1. **Parental PIN** — **deferred out of this phase** (friends/family test cohort doesn't need it). Phase focuses on multi-child + CRUD + gendered face + quick mode + TestFlight. PIN + time-limit = a later phase. → Drops the prior "remaining MVP" item from this phase's scope.
2. **Interests UX** — **preset suggestion chips + free-add** (khủng long, công chúa, ô tô, động vật, …) + custom entry. Clean data, fast for a parent.
3. **Max children per device** — **soft cap 5** (block creating a 6th).
4. **TestFlight Apple account** — **ready**: paid Apple Developer Program + App Store Connect access under team `75EN938B6L`. Plan includes creating the app record + uploading a real TestFlight build (not just an IPA hand-off).
