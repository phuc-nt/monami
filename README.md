# Monami

A friendly bilingual voice companion app for young children, built by a parent for two 5-year-olds.

Monami lets kids tap a button and have natural conversations in Vietnamese and English with a warm AI companion. The app features a reactive robot face and anonymous per-device multi-child profiles—all without accounts or tracking. Audio streams directly to Google's Gemini Live and is never stored locally.

## Features

- **Bilingual voice conversations** — Vietnamese and English, low-latency (~850ms first-audio response)
- **Age-appropriate safety** — strict content policies, kid-friendly persona
- **Multi-child profiles per device** — parents create named profiles (with gender and interests); each child has persistent memory
- **Per-child memory** — after each session, the backend summarizes the chat so the companion remembers the child next time
- **Gendered robot face** — animated LED face that reacts to voice state, visually distinct for boys and girls
- **Guest mode** — quick anonymous session with no storage
- **Privacy-first** — no accounts, no ads, no analytics; audio is streamed live and never stored; only short text memories are kept

## Architecture

```
┌─────────────────────────┐          ┌──────────────────────────────────────┐
│   Flutter app            │          │   Google Cloud Run (FastAPI)          │
│   iOS · macOS            │  WSS     │                                       │
│                          │ ───────► │   • WS relay (1 Gemini session/conn)  │
│  • mic 16 kHz PCM        │  + REST  │   • REST: child profiles + memory     │
│  • playback 24 kHz PCM   │ ◄─────── │                                       │
│  • LED robot face        │          │        │                  │          │
│  • per-device profiles   │          └────────┼──────────────────┼──────────┘
└─────────────────────────┘                   ▼                  ▼
                                    Vertex AI Gemini Live    Firestore
                                    (real-time voice)        (profiles + memory)
```

**Three components:**
- **Flutter app** (`app/`) — iOS + macOS; captures mic (16 kHz PCM), plays back audio (24 kHz), shows chat and robot face. Built with `record`, `flutter_pcm_sound`, and `web_socket_channel`.
- **FastAPI backend** (`backend/`) — Python relay between the app and Gemini Live; one native-audio session per WebSocket connection; REST API for child-profile CRUD and memory management.
- **Storage & AI** — Google Cloud Run (serverless, scale-to-zero), Firestore (child profiles and memories), Vertex AI Gemini Live (voice conversation engine).

## Getting Started (Development)

### Prerequisites
- Flutter SDK (stable) with iOS/macOS enabled
- Python 3.11+
- GCP project with Vertex AI + Gemini Live enabled
- `gcloud` CLI authenticated

### Run the backend

See [`backend/README.md`](backend/README.md) for setup and local testing.

```bash
cd backend
python3 -m venv .pyenv-backend
source .pyenv-backend/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn main:app --host 127.0.0.1 --port 8000
```

### Run the app

See [`app/README.md`](app/README.md) for dependencies and configuration.

```bash
cd app
flutter pub get
flutter run -d macos  # or -d ios
```

**For cloud backend** — pass the deployment URL and API token via `--dart-define`:

```bash
flutter run -d ios \
  --dart-define=MONAMI_WS_BASE=wss://<service>.run.app/ws/voice \
  --dart-define=MONAMI_TOKEN=<secret-token>
```

The token is stored in GCP Secret Manager and never committed.

## Privacy & Data

Monami is built with privacy as a core principle:

- **Audio:** Streamed live to Google's Gemini Live and **never stored**.
- **Profiles & memories:** Tied to an anonymous device ID (UUID stored in iOS Keychain); no user accounts, no login.
- **No analytics:** No tracking, no ads, no third-party integrations.

See [Privacy Policy](https://phuc-nt.github.io/monami/privacy-policy.html).

## Release & Testing

The app is currently in TestFlight (internal + external testing).

- **App name:** Monami: Smart Friend for Kids
- **Bundle ID:** `com.phucnt.openchatbot`
- **Release notes & build instructions:** See [`app/RELEASE.md`](app/RELEASE.md)

## Project Status

**Completed (Phase 1–6):**
- Bilingual voice conversation loop with Gemini Live
- Multi-child profiles and per-device anonymous identity
- Per-child persistent memory summaries
- Gendered robot face with animation
- Guest (no-storage) mode
- TestFlight deployment

**Deferred:**
- Parental controls (PIN, session time limits)
- Android port

**Future:**
- Enhanced memory management
- Extended profile attributes
- Advanced parental dashboards

## Tech Stack

- **Frontend:** Flutter (Dart) · iOS + macOS
- **Backend:** Python · FastAPI · Pydantic
- **Cloud:** Google Cloud Run · Firestore · Vertex AI (Gemini Live)
- **Audio:** WebSocket (binary PCM frames) + REST API
- **Auth:** Anonymous per-device (no accounts)

## License

MIT

---

**Questions?** Check the [architecture docs](docs/) or open an issue.
