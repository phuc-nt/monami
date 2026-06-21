---
phase: 1
title: "Local Backend Gemini Live Relay"
status: completed
priority: P1
effort: "1d"
dependencies: []
---

# Phase 1: Local Backend Gemini Live Relay

## Overview

Small local Python backend that holds GCP creds, opens one Gemini Live session per
client connection, and relays audio both ways over a WebSocket. The brains of the
voice loop; the Flutter app is a thin client.

## Requirements

- Functional: accept a WebSocket connection; on connect, open a Gemini Live session
  with the verified config; forward client audio (16kHz PCM) to Gemini; stream
  Gemini's audio (24kHz PCM) + transcripts back to the client; handle end-of-turn
  via trailing-silence VAD; clean teardown on disconnect.
- Non-functional: low added latency over the raw API; GCP credential stays
  server-side; one focused service (<~250 LOC core), reuse spike patterns.

## Architecture

- `app/` package, NOT under `spike/` (spike is throwaway). New `backend/` at repo root.
- FastAPI + `websockets`/Starlette WS endpoint, or bare `websockets` lib. Pick FastAPI
  for a clean WS route + health check (KISS, well-trodden).
- One async task pumps client→Gemini; another pumps Gemini→client. Per-connection
  Gemini session via `client.aio.live.connect(...)`.
- Config module reuses the verified constants (model, region, language_hints,
  safety, system prompt, END_SILENCE_MS) — lift from `spike/gemini_live_direct_probe.py`
  into a clean `gemini_session_config.py` (do not import spike; copy + tidy).
- Message protocol (client↔backend WebSocket):
  - client→server: binary frames = raw 16kHz mono PCM audio chunks; a small JSON
    control frame for "end of utterance" if client-driven (else backend VAD).
  - server→client: binary frames = 24kHz PCM audio; JSON frames for transcripts
    (`{type:"in_transcript"|"out_transcript", text}`) and `{type:"turn_complete"}`.

## Related Code Files

- Create: `backend/main.py` (FastAPI app + WS endpoint + health route)
- Create: `backend/gemini_session.py` (open/manage Live session, the two pump loops)
- Create: `backend/gemini_session_config.py` (verified config: model, region,
  language_hints, safety, system prompt, audio constants, END_SILENCE_MS)
- Create: `backend/child_profile.py` (one hard-coded profile → system-prompt text)
- Create: `backend/requirements.txt` (fastapi, uvicorn[standard], google-genai, python-dotenv)
- Create: `backend/.env.example` (GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_LOCATION=us-central1, GEMINI_LIVE_MODEL)
- Create: `backend/README.md` (run instructions, ADC note)
- Create: `backend/.gitignore` (.env, env dir, __pycache__)

## Implementation Steps

1. Scaffold `backend/`; venv-equivalent env; install deps.
2. `gemini_session_config.py`: port verified config from the spike (build the
   `LiveConnectConfig` with AUDIO modality, language_hints [vi-VN,en-US], strict
   safety, bilingual system prompt + hard-coded profile text).
3. `gemini_session.py`: `async def run_session(ws)` — connect to Gemini Live; spawn
   client→Gemini pump (forward incoming PCM as `send_realtime_input(audio=Blob(...))`,
   append trailing silence on utterance end) and Gemini→client pump (forward audio +
   transcripts + turn_complete). Reuse the spike's proven flow.
4. `main.py`: FastAPI WS route `/ws/voice` calling `run_session`; `/health` route.
5. Add a tiny script-or-test that connects a local WS client, streams one Phase-0
   WAV, and prints transcripts + latency — proves the backend without Flutter yet.
6. Verify GCP credential is read from ADC/env only; never sent to client.

## Success Criteria

- [x] `uvicorn` serves `/ws/voice`; `/health` returns ok. (smoke-tested → `{"status":"ok"}`)
- [~] A local WS test streams a WAV and receives transcript + audio + turn_complete.
      Test client written (`scripts/ws_test_client.py`); relay loop proven in-process
      (two-turn test). Full audio round-trip needs real ADC → user manual run.
- [x] Verified config applied (language_hints `[vi-VN,en-US]`, trailing-silence VAD,
      strict safety BLOCK_LOW_AND_ABOVE ×4, AUDIO-only, bilingual prompt + profile) —
      asserted at import; matches spike verbatim (25600B/800ms silence math exact).
- [x] No GCP credential leaves the server (creds via ADC server-side; wire carries
      audio + transcript/control JSON only; error frame sends generic message).
- [x] Backend core stays small/focused (~290 LOC); no spike import.

## Completion Notes

Implemented `backend/`: `main.py` (FastAPI `/ws/voice` + `/health`, Starlette WS
adapter), `gemini_session.py` (per-connection relay, uplink/downlink pumps),
`gemini_session_config.py` (verified config), `child_profile.py` (1 hard-coded
profile), `scripts/ws_test_client.py`, requirements/README/.env.example/.gitignore.
Deps pinned to google-genai 2.9.0 (the Phase-0-verified version).

Code review caught + fixed two bugs the single-turn smoke test masked:
- **Single-turn relay**: the SDK's `session.receive()` ends at the first
  `turn_complete`. Wrapped it in a per-turn outer loop so the session is truly
  multi-turn (proven with a two-turn in-process test).
- **Disconnect misclassification**: `WebSocketDisconnect`/`ConnectionClosed` aren't
  `ConnectionError`, so normal disconnects logged as crashes. Fixed: adapter
  translates `WebSocketDisconnect`→`ConnectionError` at the boundary; benign tuple
  also covers `ConnectionClosed`. Also: client error frame is now generic (no
  internal detail leaked).

**User manual step before Phase 3 end-to-end**: run the backend with real ADC
(`gcloud auth application-default login`) + `backend/.env`, then
`python scripts/ws_test_client.py <16k-mono.wav>` to confirm the full audio loop.

## Risk Assessment

- **SDK shape drift** vs spike → reuse spike patterns verbatim; they're verified.
- **Backpressure/ordering** between the two pumps → use asyncio queues; keep audio
  frames ordered; don't block one pump on the other.
- **Credential leak** → assert creds only in backend env; client protocol carries
  audio/text only.
- **Latency added by relay** → measure in step 5; keep frames small (~20ms), no
  buffering beyond what's needed.
