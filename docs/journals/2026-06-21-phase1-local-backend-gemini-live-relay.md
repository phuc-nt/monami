# Phase 1 — Local Backend Gemini Live Relay

**Date:** 2026-06-21
**Plan:** `plans/260621-1933-phase1-core-voice-loop-direct-gemini/` (Phase 1 of 4)
**Commit:** `e1bfc32`

## Goal

First real code slice of the voice loop: a local Python backend that holds the
GCP credential, opens one Gemini Live native-audio session per WebSocket
connection, and relays audio + transcripts both ways. The Flutter client (Phase
2) is a thin consumer of this. No LiveKit (Phase 0 decision).

## What shipped

`backend/` (~290 LOC core, google-genai 2.9.0 — the Phase-0-verified version):

- `main.py` — FastAPI `/ws/voice` + `/health`; `_StarletteWsAdapter` keeps the
  relay framework-agnostic (duck-typed `send_bytes`/`send_text`/`iter_messages`).
- `gemini_session.py` — `run_session(ws)`: two asyncio pumps (uplink
  client→Gemini, downlink Gemini→client) raced via `asyncio.wait(FIRST_COMPLETED)`.
- `gemini_session_config.py` — verified config lifted + tidied from the spike.
- `child_profile.py` — one hard-coded profile (Vy, 5, likes Elsa) → prompt text.
- `scripts/ws_test_client.py` — standalone WS client; proves the loop without Flutter.

Wire protocol: binary frames = PCM audio (16k up / 24k down); JSON text frames =
control (`end_utterance` up; `in_transcript`/`out_transcript`/`turn_complete`/`error` down).

## Carried verbatim from Phase 0 (do not change without re-validating)

us-central1 · `gemini-live-2.5-flash-native-audio` · `language_hints=["vi-VN","en-US"]`
· end-of-turn = trailing silence + server VAD (the model ignores `audio_stream_end`)
· `response_modalities=["AUDIO"]` only · strict safety `BLOCK_LOW_AND_ABOVE` ×4 ·
memory = system-prompt context-stuffing. Silence math: 16k×2B×800ms = 25600B, exact.

## Two bugs the code review caught (smoke test had masked both)

1. **Single-turn relay.** The SDK's `session.receive()` generator ends at the
   first `turn_complete` (`live.py:456-459`). `_downlink` called it once → the
   companion could answer exactly one utterance, then the session tore down. The
   spike's one-shot-per-turn pattern was wrongly stretched over a long-lived
   connection. Fix: wrap `receive()` in a per-turn outer loop; exit when it
   yields nothing (session closed). Proven with a two-turn in-process test.

2. **Disconnect misclassification.** `WebSocketDisconnect` and `ConnectionClosed`
   are **not** `ConnectionError` subclasses, so normal client disconnects were
   logged as crashes + triggered a doomed error-frame send. Fix: the adapter
   translates `WebSocketDisconnect`→`ConnectionError` at the boundary (core stays
   framework-agnostic); benign tuple also covers `ConnectionClosed`. Plus: the
   client-facing error frame is now generic ("session error") so a Gemini
   `APIError` can't leak the project id over the wire.

Lesson: a happy-path single-turn test passing is exactly why these slipped — the
relay's multi-turn + disconnect behavior needed their own checks.

## Security

GCP credential is ADC-only, server-side; the client↔backend wire carries audio +
transcript/control JSON, never credentials/project id/model id. Verified:
`backend/.env`, the python env dir, pycache, and all child audio are gitignored;
secret scan on the commit was clean.

## State

- Phase 1: **done** (server boots, `/health` ok, config asserted, two-turn relay
  proven). Full audio round-trip needs real ADC → **user manual run step** before
  Phase 3 end-to-end (documented in `backend/README.md`).
- Phase 2 (Flutter macOS client): **blocked on installing Flutter** (not on the
  machine — flagged in plan validation).

## Carry-forward / open

- Run the backend with real ADC + a 16kHz-mono WAV through `ws_test_client.py` to
  confirm the live audio loop (transcripts + audio + latency) before Phase 3.
- Phase 2 starts with: install Flutter SDK + macOS desktop toolchain, then a
  ~30-min audio-plugin spike (16k PCM capture / 24k PCM playback) before UI.
