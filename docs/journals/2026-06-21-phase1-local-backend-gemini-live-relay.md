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

## Live validation (real ADC, real child voices)

Ran the backend with real ADC (`gcloud auth application-default login`, quota
project `monami-kids-spike`) + both children's clips through `ws_test_client.py`
(clips re-encoded to 16k mono PCM in `/tmp`, deleted after — never in the repo):

| Child | Input transcript (vi, hints correct) | Reply (warm, profile felt) | first-audio |
|-------|--------------------------------------|----------------------------|-------------|
| Vy | "Bà ơi tại sao phép thuật của Elsa lại có nhiều phép thuật vậy bà?" | "À, Vy thích Elsa lắm đúng không? …Vy thấy phép thuật đó có đẹp không?" | **509 ms** |
| Phong | "Bạn ơi, tại sao xe ô tô lại có bốn bánh?" | "Chào Vy! Xe ô tô có bốn bánh để chạy cho thật vững vàng…" | (see note) |

Confirmed end-to-end: real audio → correct VN transcript (`language_hints`) →
spoken bilingual reply (24k PCM, played back fine). **first-audio 509 ms < 1.2 s
target** (better than Phase 0's ~850 ms). Hard-coded profile (Vy/Elsa) reflected
naturally — bot greets by name + references the interest; tone warm, short, ends
with an open question; safe.

**Measurement caveat (for Phase 4):** Phong's turn logged `first_audio≈0.2ms` —
a test-client artifact: response audio began streaming before the `end_utterance`
flush completed, so the `t_user_end` anchor was wrong for that turn. The real
latency was fine; the anchoring needs fixing before Phase 4's decision-grade
latency measurement.

**Single hard-coded profile = "Vy"**, so the bot greeted Phong as "Vy". Correct
by design — per-child profiles are a later phase, not a Phase 1 bug.

## State

- Phase 1: **DONE + live-validated** (server boots, `/health` ok, config asserted,
  two-turn relay proven, **real audio round-trip confirmed with both kids**).
- Phase 2 (Flutter macOS client): **blocked on installing Flutter** (not on the
  machine — flagged in plan validation). Target device confirmed: iPad/phone, so
  Flutter (one codebase) is the right client; build macOS desktop first, port later.

## Carry-forward / open

- **Phase 4:** fix the test-client latency anchor (audio can start before the
  `end_utterance` flush) before decision-grade latency numbers.
- **Phase 2 starts with:** install Flutter SDK + macOS desktop toolchain (+ Xcode
  CLT), then a ~30-min audio-plugin spike (16k PCM capture / 24k PCM playback)
  before building UI.
