# Publish-prep phase 4: gendered robot face

**Date:** 2026-06-23
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (phase 4 of 6)

## Goal

Make boys and girls see visually distinct robot faces (the brainstorm decision
was distinct faces, not color-only), keeping all five expressions + the same
animation. The long pole of the phase — subjective art on a 32×20 LED grid.

## What shipped

- `robot_face.dart` — `enum FaceVariant {girl, boy, neutral}` + `faceVariantFor`.
  The painter takes a `variant`; the **animation/expression core is untouched**
  (blink, eye-dart, happy hop, sparkle, breathing, mouth states). Only static
  shape decoration differs per variant:
  - **girl** — rounded eyes + a small outer **lash flick** + a **bow** on top.
  - **boy** — **square** (untrimmed) eyes + an **antenna stalk** on top.
  - **neutral** — the original gender-agnostic face (guest / unspecified).
  Accents (`_Eye.lash`, `_Face.antenna`) sit outside the eye box with a clear gap;
  the antenna is suppressed when sleepy. `shouldRepaint` includes the variant.
- `app_theme.dart` — `paletteFor(ChildGender)` (girl pink / boy blue / neutral
  grey) as the single per-child color source.
- `profile_picker.dart` / `main.dart` — both card + voice screen thread the
  variant + palette from the child's gender; guest/null → neutral.

## Design process (avoiding the art rabbit hole)

First pass tried a per-eye eyebrow for the boy; at LED density it merged with the
square eyes into a heavy slab (verified by dumping comparison PNGs). Dropped the
brow — boy now reads "stronger" purely via square eyes + antenna, which is clean
and distinct. The three variants were rendered side-by-side and **approved by the
user** before locking in.

## Carry-overs from phase 3 (done here)

- Moved `childTint` out of the picker into `app_theme.paletteFor` (main.dart no
  longer imports the picker for color).
- Hoisted the single `ChildService` out of `MonamiApp.build()` into a stateful
  holder — created once (`late final`), disposed (closes the http client) — so it
  isn't rebuilt per build now that more screens depend on it.

## Verification

- 34/34 unit tests; `flutter analyze` clean. Render test extended to every
  expression × variant, plus a **pixel-distinctness test** (girl ≠ boy ≠ neutral
  at a pinned animation frame) so a refactor can't silently disable a variant.
- **Simulator E2E (iPhone 17 Pro vs live backend):** created a girl + a boy
  child; opening each child's voice screen renders the correct `FaceVariant`
  (girl→girl, boy→boy), asserted by scoping to the top route's Scaffold. No leak.

## Review

Verdict: safe, all 5 criteria MET, no blockers. Added the pixel-distinctness test
(reviewer's M1). Left a pre-existing unreachable sparkle branch (L1) for a future
robot-face touch — it predates this phase.

## State

Phase 4 complete + reviewed. Next: phase 5 (quick guest mode — most of it already
routes correctly; finalize the no-persist UX), then 6 (TestFlight). Parental PIN +
time-limit still deferred.
