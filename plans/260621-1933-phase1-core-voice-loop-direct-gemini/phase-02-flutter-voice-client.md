---
phase: 2
title: "Flutter Voice Client"
status: pending
priority: P1
effort: "1-1.5d"
dependencies: [1]
---

# Phase 2: Flutter Voice Client

## Overview

Thin Flutter desktop app (macOS first): capture mic as 16kHz mono PCM, send to the
backend over WebSocket, receive 24kHz PCM and play it, show a minimal push-to-talk
UI. No character/UI polish — just enough to talk and listen.

## Requirements

- Functional: connect to `ws://localhost:.../ws/voice`; push-to-talk capture; stream
  PCM up; play returned PCM; show simple state (idle / listening / speaking) and the
  live transcripts (for dev visibility).
- Non-functional: low capture→send and receive→play latency; runs as a macOS desktop
  app; clean reconnect on backend restart.

## Architecture

- New `app/` Flutter project (desktop enabled: `flutter create --platforms=macos app`).
- Audio plugin decision (OPEN Q1): need 16kHz mono PCM capture + 24kHz PCM playback.
  Candidates: `record` (capture, supports PCM stream) + a raw-PCM player, or a
  combined low-level plugin. Spike one plugin combo early; if desktop PCM playback is
  painful, fall back to feeding a small audio buffer. Document the choice.
- WebSocket via `web_socket_channel`. Binary frames = audio; JSON frames = transcripts/control.
- Simple state machine: idle → (hold to talk) listening/streaming → release → waiting →
  speaking (playing response) → idle.
- Keep layers thin: `audio_capture.dart`, `audio_playback.dart`, `voice_socket.dart`,
  `voice_controller.dart` (state), `main.dart` (UI).

## Related Code Files

- Create: `app/` (Flutter project, macOS platform)
- Create: `app/lib/audio_capture.dart` (mic → 16kHz mono PCM stream)
- Create: `app/lib/audio_playback.dart` (24kHz PCM → speaker)
- Create: `app/lib/voice_socket.dart` (WS connect, send audio, parse frames)
- Create: `app/lib/voice_controller.dart` (state machine, ties capture/socket/playback)
- Create: `app/lib/main.dart` (push-to-talk button, state + transcript display)
- Modify: `app/macos/Runner/Info.plist` (microphone usage permission)
- Modify: `app/pubspec.yaml` (audio + websocket deps)

## Prerequisite (validation finding)

<!-- Updated: Validation Session 1 - Flutter not installed -->
Flutter is NOT yet installed on this machine. Before step 1: install the Flutter
SDK and enable macOS desktop (`flutter config --enable-macos-desktop`), confirm
`flutter doctor` is green for macOS (needs Xcode command-line tools). Blocks all of
Phase 2.

## Implementation Steps

1. `flutter create --platforms=macos app`; add mic permission to entitlements/Info.plist.
2. Add deps; spike the chosen audio plugin: confirm 16kHz mono PCM capture and 24kHz
   PCM playback work on macOS desktop (a 30-min throwaway check before building UI).
3. `audio_capture.dart`: start/stop capture, emit PCM chunks (~20ms).
4. `audio_playback.dart`: enqueue + play streamed 24kHz PCM with minimal buffering.
5. `voice_socket.dart`: connect; send audio binary frames; on receive, route audio→
   playback and JSON→controller.
6. `voice_controller.dart` + `main.dart`: push-to-talk button, state display, show
   in/out transcripts for dev.
7. Run against the Phase 1 backend; confirm a spoken round-trip works.

## Success Criteria

- [ ] macOS app launches, asks mic permission, captures audio.
- [ ] Push-to-talk streams PCM to backend; response audio plays back.
- [ ] Transcripts (in/out) shown for dev.
- [ ] Reconnects cleanly after a backend restart.
- [ ] Audio plugin choice documented; PCM formats correct (16k in / 24k out).

## Risk Assessment

- **Audio plugin PCM mismatch** (sample rate/format) → resample/convert at the edge;
  verify formats in step 2 before building further.
- **macOS mic permission/entitlements** → set Info.plist + entitlements; test on a
  real launch (not just debug).
- **Playback gaps/choppiness** from streaming PCM → small jitter buffer; tune chunk size.
- **Web target later** — do NOT block Phase 1 on web; note web audio (AudioWorklet)
  as separate later work.
