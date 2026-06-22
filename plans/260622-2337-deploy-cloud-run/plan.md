---
title: "Deploy Backend To Cloud Run"
description: "Run the voice backend 24/7 on GCP Cloud Run (no laptop): containerize it, move per-child memory to Firestore, gate the WS with a shared-secret token, deploy scale-to-zero, and make the Flutter app target the cloud URL with a friendly cold-start UI."
status: pending
priority: P2
created: 2026-06-22
blockedBy: [260622-2119-two-profiles-and-memory]
---

# Deploy Backend To Cloud Run

## Overview

Today the backend runs on the laptop with `gcloud` ADC and stores memory as local
JSON. To let the two kids use the app any time without the laptop on, deploy the
backend to **GCP Cloud Run** (serverless, WebSocket-capable, runs as a service
account so no key file), move memory to **Firestore** (so it survives container
restarts), gate the WS with a **shared-secret token** (so a stranger with the URL
can't burn Gemini quota or touch a child's memory), and point the Flutter app at
the cloud URL with a friendly **cold-start UI** (since scale-to-zero means the
first connect waits a few seconds).

## Decided architecture

- **Platform:** Cloud Run, **scale-to-zero** (near-free; ~3-8s cold start accepted).
  WebSocket supported; per-session is minutes (well under the 60-min cap).
- **Credential:** the Cloud Run service's **service account** with the Vertex AI
  User role → the existing `genai.Client(vertexai=True, project, location)` ADC
  path works unchanged in the cloud (no key file).
- **Memory:** **Firestore** (GCP-native; same service account, no extra
  credential). Swap `profile_store` (JSON) for a Firestore-backed implementation
  behind the same `load_memory`/`save_memory` interface.
- **Auth:** a **shared-secret token** the app sends on WS connect; the backend
  rejects mismatches before opening a Gemini session.
- **Region:** `us-central1` (must match the native-audio model + Firestore location).

## Architecture (where it hooks in)

```
Flutter app  → wss://<service>.run.app/ws/voice?profile=<id>  (+ token)
                • cold-start UI: "đang đánh thức…", talk button locked until ready
Cloud Run (service account = Vertex AI User)
  • token check at WS accept (reject if missing/wrong)
  • google-genai live (ADC via the service account) → Gemini Live @ us-central1
  • memory via Firestore (load on connect, save on session end)
Firestore (collection: child memory docs)
```

Current touchpoints (from scout):
- `backend/profile_store.py` — JSON load/save → Firestore (same 2-function API).
- `backend/main.py` `ws_voice` — add the token check at accept; read token from
  env (Cloud Run secret/env).
- `backend/requirements.txt` — add `google-cloud-firestore`.
- New: `backend/Dockerfile`, `.dockerignore`, deploy doc/script.
- `backend/gemini_session.py` — uses `cfg.project_and_location()` already; confirm
  it resolves from the Cloud Run env (project auto-detected; region from env).
- `app/lib/voice_controller.dart` / `voice_socket.dart` — target the cloud URL +
  send the token; surface a "connecting/cold-start" state.
- `app/lib/main.dart` — cold-start UI: status + locked talk button + retry.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Containerize And Firestore Memory](./phase-01-containerize-and-firestore-memory.md) | ✅ Completed |
| 2 | [Auth And Cloud Run Deploy](./phase-02-auth-and-cloud-run-deploy.md) | Pending |
| 3 | [Flutter Cloud URL And Cold Start UX](./phase-03-flutter-cloud-url-and-cold-start-ux.md) | Pending |

## Acceptance criteria (whole plan)

- Backend runs on Cloud Run; the app connects over `wss://…` and a full spoken
  conversation works end-to-end from the cloud.
- Memory persists in Firestore: talk → memory saved → app reconnects later (even
  after a cold start / new container) → memory recalled. Per-child, isolated.
- The GCP credential is the service account (no key file in the repo or image).
- A connect without the correct token is rejected (no Gemini session opened).
- Cold start is handled in the UI: the child sees a friendly "waking up" state and
  CANNOT trigger broken actions (talk button locked) until the backend is ready;
  a timeout offers a retry.
- Local dev still works (laptop ADC + local run unchanged).
- No secrets committed; child memory + audio never in the repo/image.

## Scope OUT (later)

Parental PIN; multi-user accounts/auth provider; custom domain/TLS cert (use the
default run.app URL); autoscaling tuning / min-instances (stay scale-to-zero);
CI/CD pipeline; observability/alerting; mobile (iOS/Android) store builds.

## Privacy / security

- Service account scoped to least privilege (Vertex AI User + Firestore access).
- Token stored as a Cloud Run secret/env, and in the app via a config not
  committed (e.g. `--dart-define` / a gitignored config), NOT hardcoded in source.
- Firestore holds child names + chat summaries → private; rules locked to the
  service account (no public client access). No audio ever stored.
- `.dockerignore` excludes `.env`, `profiles/`, the venv, caches, any audio.

## Dependencies

- Blocked by (satisfied): 2 profiles + memory (the store interface this swaps).
- External: a GCP project with billing, Vertex AI + Firestore enabled; `gcloud`
  CLI for deploy; Docker (or Cloud Build) to build the image.
- New package: `google-cloud-firestore`.

## Open questions (resolve during execution)

1. Firestore mode (Native vs Datastore) + database id — use Native, default db,
   `us-central1`; confirm at setup.
2. Token delivery on a WebSocket: query param (`?token=…`) vs a subprotocol/header.
   Default: query param alongside `?profile=` (simplest; URL is wss/TLS-encrypted).
   Revisit if we want it out of URLs/logs.
3. Build path: local `docker build` + `gcloud run deploy`, or `gcloud run deploy
   --source .` (Cloud Build). Default: `--source .` (no local Docker needed).
4. Cold-start "ready" signal: rely on the WS connecting + first session opening,
   or add a lightweight readiness ping. Default: treat "socket open" as ready;
   add a `/health` warmup call from the app if needed.
