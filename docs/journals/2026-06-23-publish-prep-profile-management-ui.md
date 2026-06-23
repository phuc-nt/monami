# Publish-prep phase 3: profile-management UI

**Date:** 2026-06-23
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (phase 3 of 6)

## Goal

Replace the hardcoded vy/phong picker with a real, device-scoped
profile-management UI on top of the phase-1/2 backend + service: list children,
add/edit a child, and view/edit/clear the memory the companion keeps — all from
the app, parent-facing.

## What shipped

- `interests_chips.dart` — preset suggestion chips + free-add (caps 10×30).
- `child_form_screen.dart` — create/edit one child: name (required ≤20), gender
  (required boy/girl — **never neutral**; SegmentedButton), age slider 1–12,
  interests chips. 409 → "đủ 5 bé" message; pops `true` on save.
- `child_manage_screen.dart` — parent-facing: edit profile, view/edit (dialog)/
  clear (confirm) memory, delete child (confirm); refetches after each mutation.
- `profile_picker.dart` — reworked from hardcoded StatelessWidget to a
  service-backed StatefulWidget with **three states that are never conflated**:
  loading (spinner) / loaded-empty (successful `[]` → "Thêm bé để bắt đầu" + add
  card) / error (fetch failed → retry, **not** empty). Emits `Child`; "+ Thêm bé"
  hidden at the cap of 5; gear per card → manage; "Khách" → guest. Stand-in
  `childTint(gender)` until phase-4 palette.
- `main.dart` — `main()` is async: `WidgetsFlutterBinding.ensureInitialized()` +
  `DeviceIdentity().ensure()` → `MonamiApp(deviceId)`, which builds one
  `ChildService`. `VoiceHome` now takes `Child?` (null = guest) via a `.guest()`
  ctor and derives profileId/displayName/tint with a neutral fallback.

## The red-team-critical invariant

The picker's three states must never be conflated — a failed fetch rendering as
"empty" would invite a parent to re-create a child (duplicate). `_load` sets
`error` only on `ChildServiceException`, `loaded` on any 2xx incl. `[]`; the
smoke test asserts a failed fetch shows the error/retry state, not empty.

## Verification

- 32/32 app tests; `flutter analyze` clean.
- **Interactive visual E2E on iPhone 17 Pro simulator vs the live local backend:**
  empty → add child (form, gender, save) → card shown → manage → edit memory →
  clear → delete → back to empty, all driving the real widgets; backend created
  `devices/{id}/children/` with zero errors and no leak into real data. Captured
  the empty-state screen (Baloo font, dark theme, add card + Khách entry).

## Review fixes (all landed before finalize)

- **H1** double-tap on add/gear/edit pushed two routes (→ double-create) — added
  in-flight `_navigating` guards in the picker + manage screen.
- **H2** unused import in the smoke test (analyze is now actually clean).
- **M1** an empty memory-edit save silently cleared memory, bypassing the
  clear-confirm — empty edit is now a no-op.
- **M2** `InterestsChips.onChanged` leaked its internal list by reference — now
  emits a copy.
- **M3** swipe/system back didn't carry the "changed" flag — `PopScope` now
  intercepts all pops so the picker always refetches.

## Carry-forward (folded into phase 4)

- Move `childTint` into the palette module (`paletteFor`) so `main.dart` stops
  importing the picker for color.
- Hoist the single `ChildService` out of `MonamiApp.build()` into a stateful
  holder (rebuilt per build today — negligible, but more screens depend on it).

## State

Phase 3 complete + reviewed. Next: phase 4 (two gendered robot-face variants),
then 5 (guest mode), 6 (TestFlight). Parental PIN + time-limit still deferred.
