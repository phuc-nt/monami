---
phase: 1
title: "Containerize And Firestore Memory"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: []
---

> **Completed (local-verified; deploy is Phase 2).** `profile_store.py` now
> dispatches `load_memory`/`save_memory` (unchanged signatures) to a JSON backend
> (local default) or Firestore (`MEMORY_BACKEND=firestore`); `gemini_session.py`
> untouched. Firestore client is lazy (import doesn't touch GCP), errors are
> swallowed+logged so storage never breaks the session, doc-id is path-safe.
> `Dockerfile` + `.dockerignore` added; the exact container CMD
> (`uvicorn … --port $PORT`) was run locally and served `/health`. Firestore calls
> reached real GCP (got "API not enabled" → graceful "") — enabling the API is a
> Phase 2 setup step. Code review: clean (no Critical/High); added a loud warning
> when `MEMORY_BACKEND` is mistyped (would silently lose memory on Cloud Run) +
> a startup log of the active backend.

# Phase 1: Containerize And Firestore Memory

## Overview

Make the backend cloud-ready WITHOUT deploying yet: a Docker image, and memory
moved from local JSON to Firestore behind the same `load_memory`/`save_memory`
interface. Both are verifiable locally (build the image; run against Firestore
with local ADC) before Phase 2 puts it on Cloud Run.

## Requirements

- Functional: `profile_store` reads/writes each child's memory in Firestore (one
  document per child); the rest of the code is unchanged (same 2-function API).
  The image runs the FastAPI app with uvicorn on the `$PORT` Cloud Run provides.
- Non-functional: image is small and reproducible; local dev still works (ADC);
  missing/empty Firestore doc returns "" (first-session behavior preserved); no
  audio stored; secrets/venv/profiles excluded from the image.

## Architecture

- **Firestore store** — rewrite `backend/profile_store.py` to use
  `google-cloud-firestore`:
  - One collection (e.g. `child_memory`), doc id = `profile_id`, fields
    `{summary, updated_at}`.
  - `load_memory(profile_id) -> str`: get the doc; return `summary` or "" if
    missing; tolerate errors (log + return "") so the session path never breaks.
  - `save_memory(profile_id, summary, updated_at)`: set/merge the doc.
  - A lazily-created module-level `firestore.Client()` (uses ADC → service account
    in the cloud, or local ADC in dev). Keep the path-safe id behavior conceptually
    (profile ids are a fixed small set anyway).
- **Dockerfile** — slim Python base, install `requirements.txt`, copy `backend/`,
  run `uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}`. Cloud Run sets `$PORT`.
- **.dockerignore** — exclude `.env`, `profiles/`, `.pyenv-backend/`, `__pycache__`,
  `scripts/` test artifacts, any audio.
- **requirements.txt** — add `google-cloud-firestore`.

## Related Code Files

- Modify: `backend/profile_store.py` (JSON → Firestore; same interface)
- Modify: `backend/requirements.txt` (add google-cloud-firestore)
- Create: `backend/Dockerfile`
- Create: `backend/.dockerignore`
- Modify: `backend/README.md` (Firestore note; local dev unchanged; build note)

## Implementation Steps

1. Add `google-cloud-firestore` to requirements; install in the local env.
2. Rewrite `profile_store.py` against Firestore; keep `load_memory`/`save_memory`
   signatures identical so `gemini_session.py` needs no change.
3. Local verify (with `gcloud` ADC + Firestore enabled in the project): a small
   script round-trips a memory doc; confirm `load_memory` returns "" for a new id.
4. Write the `Dockerfile` + `.dockerignore`; `docker build` (or `gcloud builds`)
   succeeds; the container starts and serves `/health` on `$PORT`.
5. Confirm the existing WS test client still works against the containerized
   backend locally (profile + memory via Firestore).

## Success Criteria

- [ ] `profile_store` reads/writes child memory in Firestore; same interface.
- [ ] First session for a child loads "" (no doc yet); after a session the doc
      exists and is reloaded next time.
- [ ] `gemini_session.py` unchanged (interface preserved).
- [ ] Docker image builds; container serves `/health` and `/ws/voice` on `$PORT`.
- [ ] Local dev still works; no secrets/venv/profiles/audio in the image.

## Risk Assessment

- **Firestore not enabled / wrong location** → enable Firestore (Native mode) in
  the project, same region; document the one-time setup.
- **Firestore client error breaks a session** → load/save are guarded (log +
  fallback to "" / no-op) so the voice loop never crashes on a storage hiccup.
- **Image too big / slow cold start** → slim base, minimal layers; cold start is
  accepted but keep the image lean.
- **Local ADC vs cloud SA divergence** → both use ADC via `firestore.Client()`;
  test locally with ADC, deploy with the SA in Phase 2.
