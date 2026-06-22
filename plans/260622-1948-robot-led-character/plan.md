---
title: "Robot LED Character"
description: "Cute pixel-art LED robot face for the voice companion: expressions driven by voice state (idle/listening/speaking/disconnected + a happy pulse). Pure Flutter CustomPainter, no Rive."
status: pending
priority: P2
created: 2026-06-22
blockedBy: [260621-1933-phase1-core-voice-loop-direct-gemini]
---

# Robot LED Character

## Overview

Replace the plain status banner with a friendly **pixel-art LED robot face** — the
thing the 5-year-old actually relates to. The face is an LED dot-matrix screen
that changes expression with the voice state the controller already emits:

- `idle` → calm, blinking eyes + small smile
- `listening` → big attentive eyes (the child is talking)
- `speaking` → animated mouth (companion is replying)
- `disconnected` → sleepy "zzz" / closed eyes
- **happy pulse** → a brief delighted grin right after the child finishes a turn

Pure Flutter: a `CustomPainter` draws an LED grid; an `AnimationController` drives
blinks / mouth movement. **No Rive, no external assets, no audio lip-sync** — state
animation only (decided). The transcript chat becomes hidden by default with a
small dev toggle to show it.

## Decided design

- Style: **pixel-art LED dot-matrix** (lit/unlit cells on a dark rounded screen).
- Expressions: 4 voice states **+ a happy/celebrate pulse** on turn completion.
- Transcript: **hidden by default**, a dev toggle (small icon button) reveals it.
- Tech: `CustomPainter` + `AnimationController`; no new packages.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Robot Face Painter](./phase-01-robot-face-painter.md) | ✅ Completed |
| 2 | [Wire To Voice States](./phase-02-wire-to-voice-states.md) | Pending |

## Acceptance criteria (whole plan)

- An LED robot face fills the main screen, cute and readable for a 5-year-old.
- Face expression matches the live voice state (idle/listening/speaking/disconnected).
- A brief happy expression plays when the child finishes a turn (turn_complete).
- Idle has subtle life (eye blink) so it doesn't look frozen.
- Transcript chat is hidden by default; a dev toggle shows/hides it.
- No regression to the working voice loop; `flutter analyze` clean; app builds + runs.

## Scope OUT (later)

Audio-amplitude lip-sync; multiple character skins; per-child characters; sound
effects; Rive; color theming controls.

## Dependencies

- Blocked by (satisfied): the core voice-loop plan — `VoiceController` already
  emits the states this drives (`app/lib/voice_controller.dart`).
- No new packages. Flutter `CustomPainter` + `AnimationController` only.

## Notes

- The controller currently has no explicit "happy" signal — Phase 2 adds a short
  transient (e.g. an `onTurnComplete` callback or a momentary flag) so the face
  can celebrate without adding a real state to the machine.
- Test mic limit unchanged (AirPods on the Mac mini); the face is visual-only so
  it's verifiable without a mic by faking states in a widget test/preview.
