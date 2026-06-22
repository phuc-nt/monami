---
phase: 2
title: "Flutter Voice Client"
status: completed
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

- [x] macOS app launches, asks mic permission, captures audio.
- [x] Streams PCM to backend; response audio plays back. (interaction is
      TAP-TO-TOGGLE, not push-to-talk — see Completion Notes)
- [x] Transcripts (in/out) shown for dev — as a scrolling chat history.
- [x] Reconnects cleanly after a backend restart ("Kết nối lại" button + auto
      disconnected state).
- [x] Audio plugin choice documented; PCM formats correct (16k in / 24k out).

## Completion Notes

Live-validated: 10+ continuous back-and-forth turns, smooth, chat history correct.

**Audio plugins (after a spike):** capture = `record` 7.1.0 (`startStream` with
`AudioEncoder.pcm16bits` — the spike confirmed it returns real PCM16 16k mono on
macOS, NOT the f32 of upstream issue #397); playback = `flutter_pcm_sound` 3.3.3
(feed-callback model, plays raw 24k PCM with low latency). `web_socket_channel`
for transport. No Swift platform channel needed.

**Interaction = TAP-TO-TOGGLE (changed from push-to-talk).** A 5-year-old can't
hold a button reliably; one tap opens the mic and streams continuously, the
backend's server VAD splits turns on natural pauses (multi-turn per mic session),
a second tap stops. This is simpler for a child and removed the need for manual
end-of-utterance + a watchdog.

**Files:** `app/lib/{audio_capture,audio_playback,voice_socket,voice_controller,
main}.dart`; macOS entitlements (audio-input + network client) + Info.plist mic
usage string.

**Code review caught + fixed before live test:** (C1) `turn_complete` jumped to
idle while audio still queued → next utterance cut off the reply; fixed with a
playback "drained" signal. (H1) silence keep-alive looped forever; now only
bridges gaps within a reply. (H2) transcript `+=` checked vs cumulative partials
→ verified Gemini sends deltas (Phase 1 output), so `+=` is correct.

**Hardware note:** Mac mini has NO mic — tests used AirPods. Bluetooth HFP mic
degrades input transcription (the "Bé" transcript label sometimes mis-detects
language), but the model still understands and replies correctly in Vietnamese.
A real device mic (iPad) will transcribe cleanly. Audio comprehension is fine;
only the displayed transcript label is noisy on the BT mic.

## Risk Assessment

- **Audio plugin PCM mismatch** (sample rate/format) → resample/convert at the edge;
  verify formats in step 2 before building further.
- **macOS mic permission/entitlements** → set Info.plist + entitlements; test on a
  real launch (not just debug).
- **Playback gaps/choppiness** from streaming PCM → small jitter buffer; tune chunk size.
- **Web target later** — do NOT block Phase 1 on web; note web audio (AudioWorklet)
  as separate later work.
