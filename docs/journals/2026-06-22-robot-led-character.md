# Robot LED Character

**Date:** 2026-06-22
**Plan:** `plans/260622-1948-robot-led-character/` (2 phases, both done)

## Goal

Give the voice companion a face the 5-year-old relates to — not a button. A cute
pixel-art LED robot whose expression follows the live conversation.

## What shipped

`app/lib/robot_face.dart` — a self-contained `RobotFace` widget: a 32x20 LED
dot-matrix on a dark rounded screen, drawn with a pure-Flutter `CustomPainter`
(no Rive, no assets, no audio lip-sync). Five expressions — `calm`, `attentive`,
`talking`, `sleepy`, `happy` — with shapes computed procedurally (eyes = rounded
blocks or arcs, mouth = curves) so they stay smooth at this resolution.

Animations off one repeating controller: blink (every state), eyes darting
left/right (idle/attentive curiosity), idle "breathing" brightness pulse, and a
happy bounce + sparkle. So it never looks frozen.

`main.dart` + `voice_controller.dart` wire it to the voice loop: `_expressionFor`
maps `VoiceState` (+ a happy pulse) to an expression; the face is the screen hero;
the transcript chat is hidden behind an AppBar dev toggle. A short happy pulse
plays when a reply finishes playing.

## Key decisions

- **Robot mask-screen face, not Rive.** The user chose a pixel-art LED robot.
  That collapsed the original Rive plan into plain Flutter painting — far simpler,
  no tooling, fully controllable, and still cute. Big YAGNI win.
- **State-driven, no audio lip-sync.** Expressions follow the voice state (which
  the controller already emits); the mouth animates on a timer during `talking`.
  No need to analyze audio amplitude.
- **Resolution + liveliness bumped on feedback.** First cut was 16x10 and only
  `calm`/`talking` animated. User wanted more pixels + more life → went 32x20 and
  added blink-everywhere, eye darting, happy bounce/sparkle, idle breathing.
- **Happy fires on playback-drain, not turn-complete.** Code review caught that
  triggering happy on `TurnComplete` (backend done *sending*) would flash happy
  mid-sentence on long replies; moved the trigger to `_onPlaybackDrained` (bot
  done *talking*).

## How it was verified without a GUI/mic

The Mac mini has no mic and I can't see the running app, so visual verification
went through a headless render harness: `test/robot_face_render_test.dart` paints
each expression (and a few animation frames) to a PNG under `DUMP_ROBOT_FACE=1`
and asserts a valid image — I inspected the PNGs directly. Caught + fixed a broken
smile/grin curve this way. `flutter analyze` clean, `flutter test` green (smoke +
render), macOS build OK. The face was confirmed wired into the real screen layout
via a one-off full-screen PNG render.

## State

- Core voice loop: done (earlier plan).
- Robot LED character: **done** — face built, animated, wired to voice state.
- Remaining for the app: per-child profiles + memory, parental PIN + time limit,
  cloud deploy, mobile/web polish. (Character was the user's priority after core.)

## Carry-forward / open

- Live "face reacts to a real conversation" confirmation is a user run step (needs
  mic + ears): `flutter run -d macos`, talk, watch the face react.
- `flutter_pcm_sound` lacks Swift Package Manager support (CocoaPods fallback
  works; harmless build warning).
- If the always-on 60fps repaint ever matters for battery, repaint could be driven
  off discrete blink/mouth phase flips instead of free-running (noted in review).
