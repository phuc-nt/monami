---
phase: 3
title: "App Profile Management UI"
status: pending
priority: P1
effort: "1.5d"
dependencies: [2]
---

# Phase 3: App Profile Management UI

## Overview

Replace the hardcoded picker with one backed by `ChildService`, and add the
create/edit-child form and a manage-child screen (edit profile + view/edit/clear
the memory the app keeps about the child).

## Requirements

- Functional:
  - **Picker:** loads children from `ChildService.listChildren()`; shows each
    child's card; adds a **"+ Thêm bé"** action and a **"Khách (quick mode)"**
    entry (guest wired in phase 5; placeholder route here).
  - **Create/Edit form:** name (required), **gender nam/nữ** (required, drives
    phase-4 face), age, interests via **preset suggestion chips + free-add**.
    Enforce **soft cap 5** (hide/disable "+ Thêm bé" at 5, backend also enforces).
  - **Manage-child screen** (long-press or a gear on the card): edit profile;
    **view** current memory summary; **edit** it (text field → `setMemory`);
    **clear** it (`clearMemory`, with a confirm); **delete child** (confirm).
  - Optimistic-ish UX: after a mutation, refresh from REST so UI matches server.
  - Empty state (no children yet) guides the parent to add one or use guest.
- Non-functional:
  - **Picker has THREE distinct states — never conflate:** (1) **loading** (spinner /
    cold-start cue — Cloud Run scale-to-zero can take several seconds on first
    fetch), (2) **loaded-empty** (a *successful* empty response → show "+ Thêm bé"),
    (3) **error** (REST failed/timed out → show a retry message that does **not**
    look like "empty"). A timeout rendering as "empty" makes a parent re-create a
    child → duplicates. Drive these off phase-2's typed errors. (Red-team finding 4b.)
  - **Name** field: max 20 chars, required, non-empty after trim; VN diacritics OK.
  - **Gender-missing fallback:** if a child arrives without a valid gender, render
    the neutral face/palette (phase 4) — never crash. (Render only; form still
    requires gender on create.)
  - Kid-safe: management actions are parent-facing; keep them out of the one-tap
    talk flow (no PIN this phase, but place them behind a deliberate gesture).
  - Match existing theme (Baloo font, dark, per-child tint).

## Architecture

- New `child_form_screen.dart` (create + edit, one widget, mode by presence of an
  existing `Child`).
- New `child_manage_screen.dart` (profile edit entry + memory view/edit/clear +
  delete).
- New `interests_chips.dart` (preset chips + free-add field) — reused by the form.
- Rework `profile_picker.dart`: data from `ChildService`, add/guest actions, cap.
- `main.dart`: routes for the new screens; picker `onPick` unchanged into voice.

## Related Code Files

- Create: `app/lib/child_form_screen.dart`, `app/lib/child_manage_screen.dart`,
  `app/lib/interests_chips.dart`.
- Modify: `app/lib/profile_picker.dart`, `app/lib/main.dart`.
- Create (tests): `app/test/child_form_render_test.dart`,
  `app/test/picker_from_service_render_test.dart` (mock service).

## Implementation Steps

0. **Startup wiring (from phase-2 review):** `main()` must
   `WidgetsFlutterBinding.ensureInitialized()` before calling
   `DeviceIdentity().ensure()` (platform channels for Keychain/prefs need it).
   Resolve `deviceId` once at startup and pass it into `VoiceHome(deviceId:)` (the
   param already exists, currently defaulting to `''`).
1. `interests_chips.dart`: preset chip set (khủng long, công chúa, ô tô, động vật, …) + free-add input → `List<String>`.
2. `child_form_screen.dart`: create/edit form with validation, gender toggle
   (**required boy/girl — never neutral**; `Child.toProfileJson` throws on
   neutral), interests chips; calls `createChild`/`updateChild`.
3. `child_manage_screen.dart`: profile-edit link, memory view/edit/clear, delete-child — all with confirms.
4. Rework `profile_picker.dart`: load via service, render cards, "+ Thêm bé" (cap 5), "Khách" placeholder, loading/error/empty states. Map a `ChildServiceException.statusCode == 409` (soft cap) to a distinct "đủ 5 bé rồi" message vs. a generic error.
5. Wire routes in `main.dart`.
6. Render tests with a mock `ChildService`; manual run against local backend: full CRUD + memory edit/clear from the UI.

## Success Criteria

- [ ] Picker lists children from the backend; reflects create/edit/delete without restart.
- [ ] Create form enforces required name (≤20 chars) + gender; interests via chips + free-add; blocked at 5 children.
- [ ] Manage screen edits profile, and **views/edits/clears** the child's memory; changes visible in Firestore.
- [ ] Delete child removes it from the list + backend (profile + memory gone).
- [ ] **Three picker states verified separately:** loading (cold-start) vs. loaded-empty vs. error-on-fetch — a forced REST error shows the **error** state (retry), NOT the empty state.
- [ ] Theme consistent (Baloo, dark, tint).

## Risk Assessment

- **Scope creep in the form** — keep fields to the agreed five; no avatar upload,
  no extra metadata this phase.
- **Race between optimistic UI + refresh** — prefer "mutate → refetch list" for
  correctness over local mutation; at this scale latency is fine.
- **Parent vs. kid surface** — management behind a deliberate gesture now; PIN is a
  later phase, note the seam so it's easy to gate later.
- **Rollback:** screens are additive; if the service-backed picker regresses, the
  voice loop itself is untouched.
