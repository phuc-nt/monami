---
phase: 4
title: "Gendered Robot Face"
status: pending
priority: P2
effort: "3d"
dependencies: [3]
---

# Phase 4: Gendered Robot Face

## Overview

Render two visually distinct robot-face variants by `gender` (female: soft/rounded
+ warm palette; male: stronger/angular + cool palette), keeping all existing
expressions (calm, attentive, talking, sleepy, happy) for both. This is the long
pole — pure art/UI, isolated so it can't block backend/CRUD.

## Requirements

- Functional:
  - `RobotFace` accepts a `variant` (from child `gender`) and renders the matching
    face shape + palette. Both variants support every existing expression + the
    `litColor` glow.
  - **Neutral/guest variant = DECIDED (no new art, no implementer choice):** the
    **current single face + a gray/neutral palette** is the neutral. It's already
    gender-agnostic — reuse it as-is for guest and for any child whose gender is
    missing/unknown. (Avoids the "girl-soft face for a guest boy" wrongness and the
    "third art set" scope creep.) `FaceVariant` = `{girl, boy, neutral}`.
  - `app_theme.dart` gains a gender→palette mapping the voice screen gradient +
    accents use, so the whole screen (not just the face) reflects gender.
  - Picker cards + voice screen both pick up the variant from the child.
- Non-functional:
  - Procedural (CanvasPainter) like today — no raster assets to bundle (keeps the
    offline/look-consistency win). If a variant truly needs an asset, bundle it +
    note licensing.
  - 60fps animations preserved; no per-frame allocation regressions.
  - Visual diff verified via the existing render-test harness (PNG dumps).

## Architecture

- `robot_face.dart`: add `enum FaceVariant { girl, boy }`; split the painter into a
  shared expression/animation core + variant-specific shape/decoration params
  (eyes, mouth curvature, antenna/accent, corner radius). Avoid duplicating the
  animation logic (DRY) — parametrize it. If the file approaches ~200 LOC, split
  variant params into `robot_face_variants.dart`.
- `app_theme.dart`: `paletteFor(gender)` → tint set; `childBackground` takes the
  gender palette.
- Consumers (`profile_picker.dart`, `main.dart`/`_GlowingFace`) pass the variant.

## Related Code Files

- Modify: `app/lib/robot_face.dart`, `app/lib/app_theme.dart`,
  `app/lib/profile_picker.dart`, `app/lib/main.dart`.
- Create (maybe): `app/lib/robot_face_variants.dart` (if LOC warrants).
- Create (tests): extend `app/test/robot_face_render_test.dart` to dump both
  variants × key expressions.

## Implementation Steps

1. Define `FaceVariant` + map from `gender`; default/guest → chosen neutral variant.
2. Refactor `robot_face.dart` painter into shared-core + variant params (no logic dup).
3. Implement girl (soft/rounded, warm) and boy (angular/stronger, cool) shape + palette.
4. `app_theme.dart`: `paletteFor(gender)` + gradient hook; thread variant through picker + voice screen.
5. Extend render tests to emit both variants across expressions; eyeball the PNGs.
6. Manual: create a girl + a boy child; confirm each screen + card shows the right face/palette and all expressions animate.

## Success Criteria

- [ ] Girl and boy children show clearly distinct faces + palettes everywhere (card + voice screen).
- [ ] All five expressions + `litColor` glow work for both variants.
- [ ] Guest/neutral has a defined look (no crash, no "missing variant").
- [ ] Animations stay smooth; render tests dump both variants; no analyzer warnings.

## Risk Assessment

- **Biggest schedule risk — subjective-art rabbit hole.** `robot_face.dart` is a
  monolithic ~334-line painter with all shapes as hardcoded constants in one
  `_faceFor()` switch; the variant refactor alone is non-trivial before a single new
  shape is drawn. At 32×20 LED resolution, "round" vs "angular" can be near
  indistinguishable. Mitigation: **write a concrete grid-coord spec for each variant
  BEFORE coding** (e.g. boy eye = sharp corners not trimmed, taller; girl eye =
  rounded, with a lash/brow accent pixel) so it's an engineering task, not an art
  loop. Timebox bumped to 3d.
- **No silent decision reversal.** The brainstorm user-decision was **distinct
  faces** (not color-only). If the variants can't be made acceptable within the
  timebox, **STOP and ask the user** whether to (a) extend, or (b) ship color-only
  for the TestFlight build and do faces as a fast-follow. Do **not** auto-fall-back
  to color-only — that silently reverses a user decision.
- **Animation regression from refactor** — keep the expression/animation core
  untouched; only shape/palette params differ. Render tests (both variants ×
  expressions) catch breakage.
- **Now depends on phase 3** (not 2): phase 3 establishes the picker/voice-screen
  structure this threads the variant through; editing it after 3 avoids conflicts on
  `profile_picker.dart` + `main.dart`.
