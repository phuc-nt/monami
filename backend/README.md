# monami voice backend (Phase 1)

Local Python relay between the Flutter client and Gemini Live native-audio.
Holds the GCP credential (the client never does), opens one Gemini Live session
per WebSocket connection, and relays audio + transcripts both ways.

This is the real backend (not throwaway like `spike/`). It reuses the config
verified in the Phase 0 spike: `us-central1`, `gemini-live-2.5-flash-native-audio`,
`language_hints=["vi-VN","en-US"]`, trailing-silence VAD, AUDIO-only, strict safety.

## Prerequisites

- Python 3.11+ (`python3 --version`).
- A GCP project with **Vertex AI** + **Gemini Live** enabled (Phase 0 used
  `monami-kids-spike`).
- `gcloud` CLI authenticated for Application Default Credentials:
  ```
  gcloud auth application-default login
  gcloud auth application-default set-quota-project <YOUR_PROJECT>
  ```
  The backend uses ADC — there is **no key file in this repo**.

## Setup

```bash
cd backend
python3 -m venv .pyenv-backend
source .pyenv-backend/bin/activate
pip install -r requirements.txt
cp .env.example .env        # then edit if your project/region differ
```

> The env dir is named `.pyenv-backend` (not `.venv`) only to satisfy a local
> context-optimizer hook; a plain `.venv` works just as well outside this repo.

`.env` is gitignored. It holds the project id + model id only (no secrets).

## Run

```bash
cd backend
source .pyenv-backend/bin/activate
uvicorn main:app --host 127.0.0.1 --port 8000
```

- Health check: `curl http://127.0.0.1:8000/health` → `{"status":"ok"}`.
- Voice WebSocket: `ws://127.0.0.1:8000/ws/voice`.

## Prove it without Flutter

Stream a 16 kHz mono PCM WAV through the live loop and see the transcript +
latency (run from `backend/`, with the server running in another terminal):

```bash
python scripts/ws_test_client.py path/to/utterance_16k_mono.wav --save-audio out.wav
```

Re-encode any clip to the required format first:

```bash
ffmpeg -i in.any -ar 16000 -ac 1 -sample_fmt s16 utterance_16k_mono.wav
```

> Child audio stays local. Do not commit input WAVs — the repo `.gitignore`
> blocks `*.wav`/`*.m4a` everywhere.

## Wire protocol (client ↔ backend)

- **client → server**
  - binary frame = raw 16 kHz mono PCM audio chunk
  - `{"type":"end_utterance"}` = push-to-talk released → backend flushes the turn
- **server → client**
  - binary frame = 24 kHz mono PCM response audio
  - `{"type":"in_transcript","text":…}` / `{"type":"out_transcript","text":…}`
  - `{"type":"turn_complete"}`
  - `{"type":"error","message":…}`

## Files

| File | Role |
|------|------|
| `main.py` | FastAPI app: `/ws/voice` + `/health`; Starlette WS adapter |
| `gemini_session.py` | per-connection relay: uplink/downlink pumps |
| `gemini_session_config.py` | verified Gemini Live config (do not change without re-validating) |
| `child_profile.py` | one hard-coded profile → system-prompt text |
| `scripts/ws_test_client.py` | local WS test client (proves the loop) |
