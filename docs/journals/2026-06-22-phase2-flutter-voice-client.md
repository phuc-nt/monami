# Phase 2 — Flutter Voice Client

**Date:** 2026-06-22
**Plan:** `plans/260621-1933-phase1-core-voice-loop-direct-gemini/` (Phase 2 of 4)

## Goal

The app the child actually touches: capture mic → stream to the Phase 1 backend
over WebSocket → play the spoken reply. macOS desktop first (iPad/web later).

## What shipped

`app/` (Flutter 3.44.2, macOS desktop):

- `lib/audio_capture.dart` — mic → 16 kHz mono PCM16 stream (`record`).
- `lib/audio_playback.dart` — feed 24 kHz PCM → speaker (`flutter_pcm_sound`),
  queue + drain signal.
- `lib/voice_socket.dart` — WebSocket transport; binary = PCM, JSON = control.
- `lib/voice_controller.dart` — state machine + conversation history.
- `lib/main.dart` — status banner, chat transcript, talk button.
- macOS entitlements (audio-input + network client) + Info.plist mic string.

Live-validated: **10+ continuous back-and-forth turns**, smooth audio, bilingual,
profile (Vy/Elsa) felt, chat history correct.

## Key decisions / findings

**Toolchain already mostly present** — only Flutter was missing (`brew install
--cask flutter`); Xcode 26.5 + CocoaPods were there. `flutter doctor` green for
macOS (Android SDK absent — fine, not targeted). Bonus: the user's iPhone showed
up as a connected device for later.

**Audio plugin spike was the gate.** Research flagged `record`'s PCM16 as suspect
on macOS (upstream issue #397: returns f32). Built a throwaway 2-button spike:
(1) capture → inspect byte count; (2) play a generated 24 kHz tone. Result:
`record` returns real PCM16 16k mono on macOS (NOT f32 — #397 not hit here), and
`flutter_pcm_sound` plays 24 kHz fine. So the simple plugin combo works — no Swift
platform channel. Saved real effort.

**Mac mini has no microphone.** First capture attempt failed with "Format
conversion is not possible" — not a plugin bug; `system_profiler` confirmed 0
input devices. Same gotcha as Phase 0. Fix: pair AirPods. (BT HFP mic degrades
the input *transcript label* — sometimes mis-detects language — but the model
still understands and replies correctly in Vietnamese. A real device mic will be
clean. Transcripts are dev-only.)

**Interaction changed push-to-talk → TAP-TO-TOGGLE.** A 5-year-old can't hold a
button reliably. One tap opens the mic and streams continuously; the backend's
server VAD splits turns on natural pauses (many turns per mic session); a second
tap stops. This removed the manual end-of-utterance + watchdog and made the
multi-turn flow natural.

**Transcript = chat history.** First cut showed only the current turn (replaced
each utterance), which read as a flicker. Switched to a scrolling `List<Turn>`
chat that auto-scrolls — the user wanted to see the whole conversation.

## Code review caught 3 bugs before the live test

1. **Reply cut off mid-sentence (Critical).** `turn_complete` jumped to idle while
   audio was still queued; the next utterance's `clear()` truncated the reply.
   Fixed with a playback "drained" signal — stay `speaking` until audio finishes
   *playing*, not just *arriving*.
2. **Silence treadmill (High).** The underrun silence-fill looped forever, keeping
   the audio engine hot. Now it only bridges gaps *within* a reply, then stops.
3. **Transcript double-concat (High, ruled out).** `+=` would double-concatenate
   if Gemini sent cumulative partials. Verified against the Phase 1 live output
   (clean, non-duplicated) → Gemini sends deltas here, so `+=` is correct.

## State

- Phase 1: done + live-validated.
- Phase 2: **done + live-validated** (10+ turns, tap-toggle, chat history).
- Phase 3 (integrate bilingual loop): goals largely met during the P2 live test
  (multi-turn, bilingual, profile felt, warm tone). Leftover: an explicit EN-only
  turn + an off-topic safety probe + tone tuning.
- Phase 4 (latency/slow-speech gate): main remaining work.

## Carry-forward / open

- Fix the dev latency anchor (audio can start before the end-of-utterance flush)
  before Phase 4's decision-grade latency numbers.
- `flutter_pcm_sound` lacks Swift Package Manager support (CocoaPods fallback
  works; harmless build warning) — revisit if Flutter drops Pods.
- Real device mic (iPad) to confirm clean transcription vs the BT-mic noise.
