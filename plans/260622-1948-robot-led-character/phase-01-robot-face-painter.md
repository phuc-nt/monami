---
phase: 1
title: "Robot Face Painter"
status: completed
priority: P2
effort: "0.5d"
dependencies: []
---

# Phase 1: Robot Face Painter

## Overview

A self-contained widget that draws a cute pixel-art LED robot face for a given
expression. No voice wiring yet — just the visual + a way to preview every
expression. Phase 2 drives it from the live voice state.

## Requirements

- Functional: render a dark rounded "screen" with a grid of LED cells; lit cells
  form eyes + mouth. Support a `RobotExpression` enum: `calm`, `attentive`,
  `talking`, `sleepy`, `happy`. Smooth eye-blink on `calm`; mouth open/close cycle
  on `talking`.
- Non-functional: pure Flutter (`CustomPainter` + one `AnimationController`); no
  packages; cheap to repaint; looks good at large size (it's the main screen).

## Architecture

- New `app/lib/robot_face.dart`:
  - `enum RobotExpression { calm, attentive, talking, sleepy, happy }`.
  - `class RobotFace extends StatefulWidget` taking `RobotExpression expression`;
    owns an `AnimationController` (repeating) for blink + mouth motion.
  - `class _RobotFacePainter extends CustomPainter` draws the LED grid from a
    small bitmap-ish description per expression (e.g. eye cells + a mouth row that
    the animation toggles). Keep the "pixel font" as simple `bool` grids or
    rect-drawing helpers — readable, not a real font engine.
- Drawing approach: a fixed dot-matrix (e.g. ~14x8 cells) inside a rounded-rect
  screen; lit cells = bright dots, unlit = faint dots (so it reads as an LED
  panel). Eyes = a couple of cells; mouth = a row whose shape/curve changes per
  expression; `talking` animates the mouth row open/closed; `calm` blinks eyes
  every couple seconds; `happy` = curved "^^" eyes + wide grin.

## Related Code Files

- Create: `app/lib/robot_face.dart` (widget + painter + expression enum)
- (No changes to voice code in this phase.)

## Implementation Steps

1. Define `RobotExpression` + the cell layout per expression (eyes/mouth grids).
2. `_RobotFacePainter`: paint the rounded screen, then the LED grid (lit/unlit
   cells), driven by `expression` + the animation value (blink phase, mouth phase).
3. `RobotFace` widget: `AnimationController` (repeat), map elapsed time → blink &
   mouth phases; `RepaintBoundary` around the painter.
4. Temporary preview: a simple screen (or wrap in the existing app behind a debug
   flag) that cycles all 5 expressions so each can be eyeballed.
5. `flutter analyze` clean; verify visually via `flutter run -d macos`.

## Success Criteria

- [x] `RobotFace` renders all 5 expressions, each clearly distinct + cute.
      (verified via headless PNG render of every expression + visual inspection)
- [x] `calm` blinks; `talking` mouth animates; motion is smooth, not jittery.
- [x] Looks good large (main-screen sized); reads as a pixel/LED face.
- [x] Pure Flutter, no new packages; `flutter analyze` clean.

## Completion Notes

`app/lib/robot_face.dart`: `RobotExpression {calm, attentive, talking, sleepy,
happy}`, a `RobotFace` `StatefulWidget` (one repeating `AnimationController` for
blink + mouth), and `_RobotFacePainter` drawing a 16x10 LED dot-matrix on a dark
rounded screen (lit cells = mint dots with a soft glow, unlit = faint dots).

Verified headlessly: `test/robot_face_render_test.dart` renders every expression
to a PNG (`DUMP_ROBOT_FACE=1`) and asserts each produces a valid image — all 5
inspected, distinct + cute. `app/lib/robot_face_preview.dart` is a standalone
dev preview (`flutter run -t lib/robot_face_preview.dart`).

Code review: zero-risk (additive; no existing file touched; voice loop unaffected).
Fixed 2 nits — `attentive` eyes now widen AND heighten (clearly distinct from
calm); render test now asserts + only writes PNGs under `DUMP_ROBOT_FACE`.

Not yet wired to voice state — that's Phase 2.

## Risk Assessment

- **Looks ugly / not cute** → iterate the cell layout; keep eyes large + a clear
  smile; preview all expressions side by side before wiring.
- **Repaint cost** → wrap in `RepaintBoundary`; only the painter animates, not the
  whole tree.
- **Over-engineering the "pixel font"** → YAGNI: hard-code per-expression cell
  grids; don't build a general font/sprite system.
