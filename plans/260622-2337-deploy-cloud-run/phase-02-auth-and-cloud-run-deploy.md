---
phase: 2
title: "Auth And Cloud Run Deploy"
status: pending
priority: P2
effort: "0.5-1d"
dependencies: [1]
---

# Phase 2: Auth And Cloud Run Deploy

## Overview

Gate the WebSocket with a shared-secret token, then deploy the container to Cloud
Run as a service account (no key file), scale-to-zero, in us-central1. After this
the backend is reachable at a `wss://…run.app` URL and rejects unauthorized
connects.

## Requirements

- Functional: a connect without the correct token is rejected at WS accept (no
  Gemini session opened, closed with a clear code). With the token, the full loop
  works from the cloud. The service runs as a service account with Vertex AI +
  Firestore access (ADC, no key file).
- Non-functional: token + region come from Cloud Run env/secret (not hardcoded);
  scale-to-zero; least-privilege SA; cost ~free at idle.

## Architecture

- **Token check** (`backend/main.py`): read `MONAMI_AUTH_TOKEN` from env; in
  `ws_voice`, compare the client-supplied token (query param `?token=`) using a
  constant-time compare; if missing/wrong, `await websocket.close(code=1008)`
  (policy violation) BEFORE opening any Gemini session. If `MONAMI_AUTH_TOKEN` is
  unset (local dev), allow (so local runs aren't blocked) — but log a warning.
- **Service account**: create/choose a runtime SA; grant `roles/aiplatform.user`
  (Vertex AI) + Firestore access (`roles/datastore.user`). Cloud Run uses it as
  the identity → the existing ADC client path works with no key file.
- **Deploy**: `gcloud run deploy monami-backend --source backend/ --region
  us-central1 --service-account <sa> --set-env-vars GOOGLE_CLOUD_LOCATION=us-central1,
  GEMINI_LIVE_MODEL=…,MEMORY_SUMMARY_MODEL=… --set-secrets MONAMI_AUTH_TOKEN=…
  --min-instances=0 --allow-unauthenticated` (the app-level token is the gate; the
  platform stays unauthenticated so the WS handshake from the app works). Confirm
  WebSocket + session timeout settings.
- **Env**: `GOOGLE_CLOUD_PROJECT` is auto-detected on Cloud Run; region + model ids
  via env; token via a Secret Manager secret.

## Related Code Files

- Modify: `backend/main.py` (token check at WS accept; env-driven)
- Modify: `backend/.env.example` (document `MONAMI_AUTH_TOKEN`)
- Create: `backend/deploy.md` (the one-time SA + roles + Firestore enable, and the
  exact `gcloud run deploy` command — a runbook, not a secret)
- Modify: `backend/README.md` (cloud run note; local dev unaffected)

## Implementation Steps

1. Add the token check to `ws_voice` (constant-time compare; reject pre-session;
   allow + warn when the env token is unset for local dev).
2. Verify locally: with `MONAMI_AUTH_TOKEN` set, a connect without/with the token
   is rejected/accepted (extend the WS test client to send `--token`).
3. One-time GCP setup (document in `deploy.md`): enable Firestore + Vertex AI;
   create the runtime SA; grant aiplatform.user + datastore.user; create the
   `MONAMI_AUTH_TOKEN` secret.
4. Deploy with `gcloud run deploy --source backend/ …` (Cloud Build builds the
   image). Capture the `wss://…run.app` URL.
5. Smoke test from a local WS client against the cloud URL (with the token): a WAV
   round-trips; memory persists in Firestore; a wrong/absent token is rejected.

## Success Criteria

- [ ] Cloud Run service is live at a `wss://…run.app` URL (us-central1).
- [ ] A connect WITHOUT the token is rejected before any Gemini session opens.
- [ ] WITH the token, a WAV round-trips end-to-end from the cloud.
- [ ] Memory persists in Firestore across a cold start (stop → new container →
      recall).
- [ ] Runs as a least-privilege service account; no key file anywhere.
- [ ] Token + config come from env/secret; nothing secret committed.

## Risk Assessment

- **Token in the URL/logs** → it's over TLS (wss); acceptable for a personal app.
  Note the option to move it to a subprotocol/header later (open question #2).
- **SA over-privileged** → grant only aiplatform.user + datastore.user.
- **Cloud Run WS quirks** (timeouts, HTTP/1.1) → confirm WS works in the smoke
  test; per-session is short so the 60-min cap is irrelevant.
- **Accidental public abuse before the token lands** → add the token check BEFORE
  the first deploy; never deploy an unauthenticated session path.
- **Cost surprise** → scale-to-zero + min-instances=0; verify no always-on
  instance; Gemini calls are the main cost and the token limits who can trigger them.
