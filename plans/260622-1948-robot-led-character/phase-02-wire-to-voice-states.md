---
phase: 2
title: "Wire To Voice States"
status: pending
priority: P2
effort: "0.5d"
dependencies: [1]
---

# Phase 2: Wire To Voice States

## Overview

Make the robot face come alive with the real conversation: map the controller's
`VoiceState` to a `RobotExpression`, add a brief **happy** pulse when the child
finishes a turn, put the face front-and-center, and hide the transcript behind a
dev toggle.

## Requirements

- Functional: the face shows `attentive` while listening, `talking` while the
  companion speaks, `calm` when idle, `sleepy` when disconnected; a short `happy`
  expression plays right after a turn completes, then returns to the live state.
  The transcript chat is hidden by default with a small dev toggle to show it.
- Non-functional: no regression to the voice loop; the happy pulse is a transient
  that doesn't add a real state to the machine; tap-to-talk still works.

## Architecture

- Map in the UI: `VoiceState → RobotExpression`
  - `disconnected → sleepy`, `idle → calm`, `listening → attentive`,
    `speaking → talking`.
- Happy pulse: add a minimal transient in `voice_controller.dart` — e.g. a
  `ValueNotifier`/callback `onTurnComplete`, or a momentary `bool justFinished`
  that the UI watches to show `happy` for ~800ms (a `Timer`), then fall back to
  the mapped state. Keep it OUT of the `VoiceState` enum (it's an effect, not a
  state). The trigger is the existing `TurnComplete` handling.
- Layout (`main.dart`): replace `_StatusBanner` as the primary visual with
  `RobotFace`; keep the talk button; move the transcript into a collapsible
  section hidden by default. Add a small dev toggle (e.g. an `IconButton` in the
  `AppBar`) that flips a `bool _showTranscript`.
- The error/reconnect affordance still needs to surface (disconnected): show the
  "Kết nối lại" button near/under the sleepy face when disconnected.

## Related Code Files

- Modify: `app/lib/main.dart` (use `RobotFace`; map state→expression; happy pulse;
  transcript hidden behind a dev toggle; keep reconnect button on disconnect)
- Modify: `app/lib/voice_controller.dart` (add the minimal turn-complete transient
  signal for the happy pulse — small, additive; no change to existing states)
- Use: `app/lib/robot_face.dart` (from Phase 1)

## Implementation Steps

1. Add the happy-pulse signal to the controller on `TurnComplete` (callback or
   transient flag); keep it additive — do not touch existing state transitions.
2. In `main.dart`, compute `RobotExpression` from `controller.state`, overridden
   by the happy pulse for its short duration.
3. Swap the layout: `RobotFace` as the hero; talk button below; transcript hidden
   by default behind a dev toggle (AppBar icon). Keep reconnect on disconnect.
4. Verify the full loop still works (tap → talk → reply) with the face reacting;
   confirm the happy pulse fires once per completed turn and reverts.
5. `flutter analyze` clean; build + run on macOS; smoke test still passes.

## Success Criteria

- [ ] Face expression tracks the live voice state in real time.
- [ ] A happy expression plays once when the child finishes a turn, then reverts.
- [ ] Transcript hidden by default; dev toggle shows/hides it.
- [ ] Disconnect shows the sleepy face + a working reconnect affordance.
- [ ] Voice loop unaffected (multi-turn still smooth); `flutter analyze` clean.

## Risk Assessment

- **Happy pulse leaks into the state machine** → keep it a UI-only transient
  driven by a callback/flag; never add it to `VoiceState`.
- **Pulse overlaps the next turn** → cap its duration (~800ms) and let the mapped
  state win afterward; if a new turn starts, the live state takes over immediately.
- **Hiding transcript hides errors** → keep the error text / reconnect button
  visible regardless of the transcript toggle.
- **Regression to voice loop** → changes are additive + UI-only; run a full
  multi-turn check before finalizing.
