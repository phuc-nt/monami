---
phase: 1
title: "Deps + flat-art kit + robot-face merge"
status: completed
priority: P2
effort: "0.5d"
dependencies: []
---

# Phase 1: Deps + flat-art kit + robot-face merge

## Overview

Lay the foundation: add `confetti`, port the flat-art kit + scene specs/worlds
as new files, and merge the enhanced robot-face rendering into the real face.
No screen behavior changes yet — pure additive infrastructure.

## Requirements

- Add `confetti: ^0.8.0` to `app/pubspec.yaml`; `flutter pub get`.
- Port (new files under `app/lib/scene/`):
  - `flat_art_kit.dart` — `FlatArt` palette, `flatArtBg`, `hardShadow`,
    `inkBorder`, `faFont`, `FaBlock`, `FaPressable`. PORT AS-IS (only fix the
    import path; it already imports `google_fonts`).
  - `scene_spec.dart` — `SceneSpec` + `ScenePainterFn`. PORT AS-IS.
  - `scene_worlds.dart` — the 6 painters + 6 `SceneSpec` consts + `allScenes`.
    PORT AS-IS (fix import paths). Add a `specForId(String id)` lookup keyed by
    `.id` (falls back to the first/`night` spec) for ThemeRotation (Phase 3).
- Merge `preview/lib/shared/robot_face.dart` enhancements INTO
  `app/lib/robot_face.dart`:
  - Add `final double bloom` ctor param, default `1.0` (baseline = current look).
  - Thread `bloom` → `_RobotFacePainter`; add it to `shouldRepaint`.
  - Replace the paint loop with the preview's: glass sheen on the screen rect,
    `corePaint` (near-white hot center), 2-pass bloom (`innerGlow` + `outerGlow`)
    scaled by `bloom`. Keep the EXACT animation/expression/variant logic (it is
    byte-identical between the two files — do not touch `_faceFor`, `_Eye`,
    `_Face`, mouth/antenna logic).
  - Keep the existing `litColor`/`screenColor` params + `FaceVariant`/
    `RobotExpression` enums (the preview's are a subset — no enum change needed).

## Architecture

```
app/lib/scene/
  flat_art_kit.dart     FlatArt tokens + FaBlock/FaPressable (ported)
  scene_spec.dart       SceneSpec + ScenePainterFn (ported)
  scene_worlds.dart     6 worlds + allScenes + specForId() (ported + 1 helper)

app/lib/robot_face.dart  (merged: + bloom param, + richer paint loop)
```

`specForId`:
```dart
SceneSpec specForId(String id) =>
    allScenes.firstWhere((s) => s.id == id, orElse: () => allScenes.first);
```

## Related Code Files

- Create: `app/lib/scene/flat_art_kit.dart`, `app/lib/scene/scene_spec.dart`,
  `app/lib/scene/scene_worlds.dart`.
- Modify: `app/lib/robot_face.dart` (add bloom + richer paint; animation untouched).
- Modify: `app/pubspec.yaml` (+confetti).
- Tests: `app/test/robot_face_render_test.dart` keeps passing (face still builds
  with default bloom; if it pins paint specifics, update minimally in Phase 4).

## Implementation Steps

1. Add `confetti: ^0.8.0`; `cd app && flutter pub get`.
2. Create the three `scene/` files from the preview (fix import paths only);
   add `specForId`.
3. Merge the face: add `bloom`, richer paint loop, `shouldRepaint` += bloom.
4. `flutter analyze` (app) — zero new issues. Confirm existing face callers
   (`_GlowingFace` in main, picker card, manage) still compile unchanged.

## Success Criteria

- [ ] `flutter pub get` resolves `confetti`.
- [ ] The 3 scene files compile; `allScenes.length == 6`; `specForId('space').id == 'space'`;
  `specForId('bogus')` returns a valid spec (no throw).
- [ ] `RobotFace(expression: ..., variant: ...)` (no bloom arg) compiles and looks
  like today; `RobotFace(..., bloom: 1.8)` glows stronger.
- [ ] `flutter analyze` clean; existing tests still build.

## Risk Assessment

- **Import-path drift when porting** → fix only the `import '../../shared/...'`
  paths to `app/lib/scene/` relatives; logic untouched.
- **Face merge changing baseline look** → bloom defaults to 1.0; the dim/lit
  alphas match the current file; only ADD passes (sheen/core/2-pass) — verify the
  no-bloom render against current visually + the render test.
- **Rollback:** new files are additive; the face change is additive (revert =
  drop bloom + restore the 3-pass loop). No callers break.
