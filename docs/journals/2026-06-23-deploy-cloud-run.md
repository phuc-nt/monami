# Deploy Backend To Cloud Run

**Date:** 2026-06-23
**Plan:** `plans/260622-2337-deploy-cloud-run/` (3 phases, all done)

## Goal

Run the voice backend 24/7 on GCP so the two kids can use the app without the
laptop on — and do it GCP-native (one credential, no external services).

## What shipped

**Phase 1 — cloud-ready (no deploy):** `profile_store.py` now dispatches
`load_memory`/`save_memory` (unchanged interface) to a JSON backend (local
default) or **Firestore** (`MEMORY_BACKEND=firestore`); `Dockerfile` +
`.dockerignore` package the app to run `uvicorn … --port $PORT`.

**Phase 2 — auth + deploy:** a shared-secret token gate at the WS accept
(constant-time compare; reject 1008 before any Gemini session; open when unset
for local dev). Deployed to **Cloud Run** (us-central1, scale-to-zero) as a
least-privilege **service account** (aiplatform.user + datastore.user) — no key
file; token in **Secret Manager**. Runbook: `backend/deploy.md`.

**Phase 3 — Flutter cloud URL + cold-start UX:** `app_config.dart` reads the
cloud URL + token via `--dart-define` (never hardcoded). A `connecting` state
covers the scale-to-zero cold start: the robot shows a "waking" look + "Đang
đánh thức bạn nhỏ…", the talk button is **locked** until the socket actually
opens, and a 15s timeout offers "Kết nối lại".

## GCP setup done (live)

Enabled Firestore + Cloud Run + Cloud Build + Secret Manager; created a Firestore
database (Native, us-central1); created the runtime SA + roles + the token secret;
deployed. Service: `monami-backend…run.app`.

## Live validation (from the cloud)

- `/health` over HTTPS → ok (cold start).
- WSS **without** token → rejected `1008` (gate works).
- WSS **with** token → full spoken loop: Phong greeted by name, dinosaur reference,
  ~2.3s.
- Memory **written to Firestore** (`child_memory/phong`) — persistent, survives
  cold start / restart. This was the whole point of the deploy.

## Bugs found + fixed during deploy/review

1. **`GOOGLE_CLOUD_PROJECT` not auto-injected on Cloud Run** (first deploy crashed
   the session). Fixed with an ADC project fallback (`google.auth.default()`) +
   set the env var explicitly on the service.
2. **`gemini-2.0-flash-001` retired** was already fixed earlier; the summary model
   is `gemini-2.5-flash`.
3. **After-dispose `socket.ready` callbacks** (back-tap during the 15s cold start)
   would `notifyListeners()` on a disposed controller → debug crash / leak. Added
   a `_disposed` guard in the callbacks + `_setState`.
4. **Token could render on screen** via a raw connect-error message (the WS URL
   carries `?token=`). All connect-error messages are now generic.

## Security

Service account = least privilege, no key file (ADC). Token in Secret Manager +
a gitignored local config — **never committed** (verified: the token value is in
no staged file). Firestore docs locked to the SA. `.dockerignore` keeps `.env`,
`profiles/`, venv, caches, tests, and audio out of the image. No audio stored.

## State

- Backend: **deployed + live on Cloud Run**, memory in Firestore.
- App: targets the cloud via `--dart-define`; cold-start UX handled.
- Remaining for the app: parental PIN + time limit; iPad/mobile store builds.

## Carry-forward / open

- Full app-from-cloud run (pick child → cold start UI → talk → memory recall) is a
  user run step (needs the cloud `--dart-define` build + a mic).
- Token is currently a URL query param (over TLS). Could move to a header/subprotocol
  later if we want it out of URLs entirely.
- Cost: scale-to-zero (~free at idle); Gemini calls dominate, gated by the token.
