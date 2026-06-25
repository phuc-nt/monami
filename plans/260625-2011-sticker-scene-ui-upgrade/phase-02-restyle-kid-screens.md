---
phase: 2
title: "Restyle picker + voice + form (real data/state)"
status: completed
priority: P2
effort: "1.5-2d"
dependencies: [1]
---

# Phase 2: Restyle picker + voice + form (real data/state)

## Overview

Restyle the 3 kid-facing screens to the Sticker-Scene look using the Phase-1 kit
+ shared scene widgets, driven by the REAL controllers/services/models. The
preview's mock-driven screens are the visual reference ONLY — logic stays real.

## Requirements

- Extract reusable, data-agnostic scene widgets into
  `app/lib/scene/scene_widgets.dart` (from the preview's `scene_flow.dart`):
  `SceneBackdrop` (animated gradient + props painter, shared 20s controller +
  RepaintBoundary), `SpeechBubble` (+ tail), `StandingRobot` (body + dark screen +
  `RobotFace` + legs). PORT these widgets ~as-is; they take a `SceneSpec` + plain
  params, no mock types.
- The app now needs a CURRENT world. Until Phase 3 lands ThemeRotation, the
  screens take a `SceneSpec` param; `MonamiApp` passes `specForId('night')` as a
  placeholder (Phase 3 swaps in the real service). Keep the screens' `SceneSpec`
  param so Phase 3 only changes the SOURCE.

### profile_picker.dart → ScenePicker styling
- Keep `_PickerState {loading, error, loaded}` + `_load()` exactly; only restyle
  each state's widgets (loading spinner + "Đang tải…", error card + "Thử lại",
  loaded grid). Error MUST stay visually distinct from empty-loaded.
- Children render as standing characters (name block + tinted body + dark screen +
  happy `RobotFace` + legs), using `paletteFor(child.gender)`/`faceVariantFor`.
- Keep: gear-per-card → `_manage` (double-tap guarded `_navigating`); "+ Thêm bé"
  card until `kMaxChildren`; guest entry → `widget.onGuest`; tap → `widget.onPick`
  (double-tap guarded at the `MonamiApp` level — keep that).
- Background = `SceneBackdrop(spec)`; headings use `spec.headingInk`.
- Keep the iPad width-cap / wrap layout intent (cap content, center) — re-express
  in the scene layout (Wrap of characters), do NOT drop tablet handling.

### main.dart VoiceHome → SceneVoice styling
- Keep `_expressionFor(controller)`, `PopScope(canPop:false)` + `_leave()` (which
  awaits `shutdown()` then pops), `_leaving` guard, cold-start lock, dev transcript
  long-press toggle on the title, `_ModeSelector` (LearningMode + debounce),
  `_TalkButton` ready/lock logic, `_StatusLine` (connecting/disconnected/error).
- Restyle: `SceneBackdrop(spec)` background; `StandingRobot(expression, variant,
  bodyColor: tint)`; a `SpeechBubble` whose copy maps the REAL `VoiceState`
  (reuse the preview `_bubble` mapping, but off the real `_controller.state` +
  `error`); scene-styled mode chips + talk button (the press-drop `FaPressable`
  feel). Keep the status line for connecting/disconnected/error (kid view hides it
  when live, as today).
- Confetti: add a `ConfettiController` (disposed in dispose); play on the
  controller's `happyPulse` (listen like the preview). Keep the existing happy-pulse
  → expression mapping in `_expressionFor`.
- Transcript view stays (dev), restyled lightly or kept Material (parent/dev-only).

### child_form_screen.dart → SceneForm styling
- Keep `Form` + `_formKey` validation, `_name` (maxLength 20, required), required
  gender (`_gender` null until picked; error "Hãy chọn bạn trai hoặc bạn gái"),
  age slider 1–12, `InterestsChips`, `_save()` (create/update via ChildService,
  409 → "Đã đủ 5 bé" message, `_saving` state), pop(true) on success.
- Restyle: `SceneBackdrop(spec)`; scene-styled name field, gender tiles
  (`FaPressable`, tinted when selected), slider (scene track color), interests
  chips, CTA (`FaPressable` ctaColor). The gender tiles still feed the SAME
  `_gender` state + validation. Reuse `InterestsChips` (keep its contract) — style
  via theme, don't fork it.

## Architecture

```
app/lib/scene/scene_widgets.dart   SceneBackdrop, SpeechBubble, StandingRobot (shared)
app/lib/profile_picker.dart        restyled; same _PickerState + load + guards
app/lib/main.dart                  VoiceHome restyled; same controller wiring + _leave + confetti
app/lib/child_form_screen.dart     restyled; same Form validation + _save
app/lib/app_theme.dart             light Baloo-2 theme; keep paletteFor() (face/body tint)
```

`app_theme.dart`: switch `buildAppTheme()` to a LIGHT Material theme (Baloo 2),
so Material parent screens (manage, dialogs) read coherently on the new look.
Keep `paletteFor()` (gendered face/body tint). `childBackground()` may stay (used
by nothing kid-facing after this) or be removed if unreferenced — verify refs first.

## Related Code Files

- Create: `app/lib/scene/scene_widgets.dart`.
- Modify: `app/lib/profile_picker.dart`, `app/lib/main.dart`,
  `app/lib/child_form_screen.dart`, `app/lib/app_theme.dart`.
- Keep (no flat-art restyle, inherit theme): `app/lib/child_manage_screen.dart`,
  `app/lib/interests_chips.dart` (reused), `app/lib/responsive.dart` (tablet).
- Tests: updated in Phase 4 (render/state tests for these screens).

## Implementation Steps

1. Extract `scene_widgets.dart` (SceneBackdrop/SpeechBubble/StandingRobot) from the
   preview, parameterized on SceneSpec + plain values.
2. Add a `SceneSpec` param to the 3 screens; `MonamiApp` passes `specForId('night')`
   (placeholder until Phase 3).
3. Restyle the picker (all 3 states) — preserve load/guards/gear/guest/cap.
4. Restyle VoiceHome — preserve controller wiring, `_leave`, locks, transcript,
   mode/talk logic; add confetti on happyPulse.
5. Restyle the form — preserve validation + `_save` + 409.
6. Light-theme `app_theme.dart`; verify manage screen + dialogs still legible.
7. `flutter analyze` clean; manual sanity that each state renders.

## Success Criteria

- [ ] Picker shows loading / error (retry) / loaded distinctly; characters tap →
  onPick; gear → manage; add card ≤5; guest works; double-tap guards intact.
- [ ] Voice: robot in world, bubble matches real state, mode chips switch mode
  (reconnect), talk uses real toggleMic + locked on connecting/disconnected, back
  runs shutdown→pop, transcript long-press works, confetti on happy pulse.
- [ ] Form: validation (name/gender/age), interests, 409 message, create/update,
  pop(true).
- [ ] All 6 worlds usable as the screens' SceneSpec; `flutter analyze` clean.

## Risk Assessment

- **Dropping a contract during restyle** → each section lists the exact behaviors;
  reviewer walks all 10 hard contracts. Highest-attention item.
- **Confetti not disposing / playing twice** → single controller, dispose in
  dispose, play only on the happyPulse listener edge.
- **Tablet layout lost** → keep `context.isTablet` sizing in the scene layouts.
- **Rollback:** screens are self-contained; revert restores the dark screens (kit
  files are unused then). app_theme revert restores dark theme.
