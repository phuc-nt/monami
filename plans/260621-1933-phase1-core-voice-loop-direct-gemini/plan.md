---
title: "Phase 1: Core Voice Loop (Direct Gemini Live, no LiveKit)"
description: "Working bilingual EN/VN voice loop on Flutter desktop ↔ local Python backend ↔ Gemini Live native-audio. No LiveKit."
status: completed
priority: P1
created: 2026-06-21
source: ../reports/phase0-go-nogo-decision-gemini-live-vn-child-speech-report.md
blockedBy: [260621-1409-phase0-spike-gemini-live-vn-child-speech]
---

# Phase 1: Core Voice Loop (Direct Gemini Live, no LiveKit)

## Overview

First real slice of the app: a child can talk to the bilingual companion by voice
and hear it answer. Flutter app (desktop-first) captures mic → local Python backend
→ Gemini Live native-audio (us-central1) → audio back to the app. One hard-coded
child profile, bilingual child-friend system prompt, strict safety. **No LiveKit** —
direct path (decided in Phase 0; LiveKit only if the slow-speech gate fails).

Proves the core experience before profiles/memory/character (later phases).

## Architecture (decided)

```
Flutter app (macOS desktop first; web fast-follow)
  • mic capture 16kHz mono PCM • playback 24kHz PCM • push-to-talk UI
        │ WebSocket (local)
  Local Python backend (FastAPI/websockets) — runs on laptop
  • holds GCP creds (client never does) • 1 Gemini Live session per connection
  • verified config: language_hints, trailing-silence VAD, strict safety,
    bilingual system prompt + hard-coded profile
        │ google-genai live (vertexai=True)
  Gemini Live native-audio — gemini-live-2.5-flash-native-audio @ us-central1
```

## Verified config from Phase 0 (MANDATORY — do not change)

- Region `us-central1`; model `gemini-live-2.5-flash-native-audio`.
- `input_audio_transcription.language_hints = ["vi-VN","en-US"]`.
- End-of-turn = trailing silence + server VAD (NOT `audio_stream_end`).
- `response_modalities = ["AUDIO"]` only (TEXT unsupported).
- Strict safety: BLOCK_LOW_AND_ABOVE on harassment/hate/sexual/dangerous.
- Memory = system-prompt context-stuffing (1 hard-coded profile this phase).
- Working reference: `spike/gemini_live_direct_probe.py` (correct SDK patterns).

## Key decision: Flutter target = macOS desktop first

Flutter **web** raw-PCM mic capture is awkward (needs Web Audio API / AudioWorklet,
no first-class Dart API; playback of raw 24kHz PCM also fiddly). **macOS desktop**
has cleaner native audio plugins. → Build/validate on **macOS desktop first**, then
port to web/mobile in a later phase. (Recorded as a decision; revisit if desktop
audio plugins disappoint.)

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Local Backend Gemini Live Relay](./phase-01-local-backend-gemini-live-relay.md) | ✅ Completed |
| 2 | [Flutter Voice Client](./phase-02-flutter-voice-client.md) | ✅ Completed |
| 3 | [Integrate Bilingual Voice Loop](./phase-03-integrate-bilingual-voice-loop.md) | ◐ Largely done in P2 (see note) |
| 4 | [Validate Slow-Speech Gate and Latency](./phase-04-validate-slow-speech-gate-and-latency.md) | ✖ Cancelled (decision made) |

> **Phase 3 note:** The integration goals (multi-turn conversation, bilingual
> EN/VN, hard-coded profile felt, warm safe tone, natural turn-taking) were all
> exercised and confirmed during the Phase 2 live test — 10+ continuous turns,
> profile reflected, smooth. Remaining nice-to-haves: a deliberate EN-only turn +
> a gentle off-topic safety probe + tone tuning (can fold into later work).
>
> **Phase 4 CANCELLED — no LiveKit (decision).** Phase 4 existed to answer one
> question: does Gemini's VAD cut off slow/hesitant kids (→ would justify LiveKit)?
> The Phase 2 live test answered it: 10+ continuous real-voice turns, no cutoffs,
> first-audio ~500ms (well under the 1.2s target), server VAD split turns
> correctly. Adding LiveKit would add a network hop (+50-150ms) and an extra
> service to solve a problem that did not occur → **YAGNI: direct Gemini Live
> stays.** Reversible: if real daily use shows cutoffs, LiveKit can be added then.
> Caveat (accepted): live testing used an adult on a Bluetooth mic, not a child
> doing long mid-sentence pauses on-device; risk judged low (Phase 0 already
> validated the kids' own voices) and easily reversible for a 2-kid personal app.
> The latency-anchor fix (dev measurement) is deferred — not needed for the
> no-LiveKit decision; revisit only if precise numbers are wanted later.

## Acceptance criteria (whole phase)

- A child speaks into the Flutter desktop app and hears a spoken bilingual reply.
- Both VN and EN inputs handled; transcripts correct (language_hints applied).
- Responses warm, age-5 appropriate, safe.
- End-to-end latency measured; ~<1.2s first-audio is the target.
- Slow/hesitant child speech tested → documented whether Gemini cuts kids off
  (the LiveKit go/no-go gate for later phases).
- GCP credential never reaches the client; backend holds it.

## Scope OUT (later phases)

LiveKit; 2 profiles + Supabase memory; Rive character + lip-sync; parental PIN +
time-limit; mobile/web polish; parent dashboard; pronunciation scoring; GCE deploy.

## Dependencies

- Blocked by (satisfied): Phase 0 spike (completed) — config verified there.
- External: GCP project `monami-kids-spike`, Vertex AI + Gemini Live, ADC.
- Tooling: Flutter SDK (desktop enabled), Python 3.x + google-genai.

## Validation Log

### Verification Results (Standard tier, 4 phases)
- Claims checked: ~10. Verified: 9 | Failed: 1 | Unverified: 0
- ✅ Verified: spike SDK patterns (language_hints, send_realtime_input, model_turn,
  turn_complete, inline_data), END_SILENCE_MS=800, region us-central1, model id,
  greenfield (no backend/ or app/ yet).
- ❌ Failed: **Flutter NOT installed** on the machine — Phase 2 prerequisite.
- 🔎 Note: stale `asia-southeast1` default in a print string at
  `spike/gemini_live_direct_probe.py:321` (cosmetic; spike is throwaway).

### Decisions confirmed (Validation Session 1)
1. **Flutter gap** → install Flutter SDK + macOS desktop toolchain at the START of
   Phase 2 (added as explicit prerequisite). Not a Phase 1 blocker.
2. **Audio plugin** → Phase 2 begins with a ~30-min plugin spike confirming 16kHz PCM
   capture + 24kHz PCM playback BEFORE building UI (already in plan).
3. **Slow-speech test input** → reuse Phase 0 clips. **Caveat:** Vy/Phong clips are
   fairly fluent → good for latency baseline but do NOT exercise long mid-sentence
   pauses. The LiveKit cutoff gate stays INCONCLUSIVE on these alone; record a
   pause-heavy clip if a firm LiveKit decision is needed. (Phase 4 updated.)
4. **Phase split** (backend → client → integrate → validate) → keep as-is.

## Open questions (resolve during execution)

1. ~~Flutter desktop mic/playback plugin choice.~~ **RESOLVED (P2):** capture =
   `record` 7.1.0 (`startStream`, `pcm16bits`, verified PCM16 16k mono on macOS);
   playback = `flutter_pcm_sound` 3.3.3 (raw 24k PCM feed). No Swift channel.
2. ~~Backend↔client transport.~~ **RESOLVED (P2):** plain WebSocket — binary
   frames = PCM, JSON text frames = control/transcripts. `web_socket_channel`.
   Low latency, smooth over 10+ turns.
3. Slow-speech test input: reuse Phase 0 kid recordings or record new clips with
   deliberate long mid-sentence pauses? (privacy: keep audio local, delete after.)
   → Still open; for Phase 4.
4. ~~Trailing-silence VAD vs client-side turn-end.~~ **RESOLVED (P2):** kept
   server-side VAD; with continuous mic streaming (tap-to-toggle) the server VAD
   splits turns on natural pauses — no client-side turn detection needed.

## Carry-forward (after P1/P2)

- **Hardware:** Mac mini has no mic; tests used AirPods (BT HFP degrades input
  transcription label, not comprehension). A real device mic transcribes cleanly.
- **Phase 4:** fix the latency anchor (audio can start before the flush); run the
  decision-grade latency + slow-speech cutoff measurement.
- **Phase 3 leftovers:** explicit EN-only turn + off-topic safety probe; tone tune.
