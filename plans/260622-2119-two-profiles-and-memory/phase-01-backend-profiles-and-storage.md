---
phase: 1
title: "Backend Profiles And Storage"
status: completed
priority: P2
effort: "0.5d"
dependencies: []
---

# Phase 1: Backend Profiles And Storage

## Overview

Turn the single hard-coded profile into a registry of two children + a small
local-JSON store that loads/saves each child's profile and memory summary. Wire
the selected child through the WS connect → session → system prompt. No
summarization yet (Phase 2) and no UI yet (Phase 3) — a query param drives it.

## Requirements

- Functional: two profiles (Vy, Phong); `/ws/voice?profile=<id>` selects one; the
  system prompt is built from that child's profile + their stored memory summary
  (empty for a first session). Unknown/missing id → safe default + a logged warning.
- Non-functional: storage is a thin module (easy to swap to Supabase later);
  text-only; profile JSON is gitignored; no credential in the files.

## Architecture

- `backend/child_profile.py`: keep `ChildProfile`; replace `DEFAULT_PROFILE` with a
  `PROFILES: dict[str, ChildProfile]` registry (`"vy"`, `"phong"`) + a
  `get_profile(profile_id)` returning the profile or a default.
- New `backend/profile_store.py`: load/save per-child memory.
  - `load_memory(profile_id) -> str` (the stored summary, "" if none).
  - `save_memory(profile_id, summary: str) -> None`.
  - Files at `backend/profiles/<id>.json`: `{profile_id, summary, updated_at}`.
    Create the dir on first save; tolerate a missing/corrupt file (return "").
- `gemini_session_config.py`: `build_system_prompt(profile, memory_text)` and
  `build_live_connect_config(profile, memory_text)` — take the selected profile +
  memory instead of importing `DEFAULT_PROFILE`. Memory folded in as a short
  "What you remember about the child" block (omit if empty).
- `gemini_session.py`: `run_session(ws, profile_id)` — resolve the profile, load
  memory, build the config from them. (Summarization added in Phase 2.)
- `main.py`: read `websocket.query_params.get("profile")`; pass to `run_session`.

## Related Code Files

- Modify: `backend/child_profile.py` (registry of 2 + get_profile)
- Create: `backend/profile_store.py` (local JSON load/save)
- Modify: `backend/gemini_session_config.py` (prompt/config take profile + memory)
- Modify: `backend/gemini_session.py` (`run_session(ws, profile_id)`)
- Modify: `backend/main.py` (read `?profile=` query param)
- Modify: `.gitignore` (ignore `backend/profiles/`)
- Modify: `backend/README.md` (note the `?profile=` param + profiles dir)

## Implementation Steps

1. `child_profile.py`: add Phong; build `PROFILES` registry + `get_profile`.
2. `profile_store.py`: JSON load/save with safe fallbacks; ensure `profiles/` dir.
3. `gemini_session_config.py`: thread `profile` + `memory_text` through prompt/config.
4. `gemini_session.py`: `run_session(ws, profile_id)` resolves + loads + builds.
5. `main.py`: read `?profile=`; default + warn if absent/unknown.
6. `.gitignore`: add `backend/profiles/`. Update `backend/README.md`.
7. Verify with the WS test client (extend it to pass `?profile=phong`): correct
   name greeted; empty memory on first run; no crash on unknown id.

## Success Criteria

- [ ] `/ws/voice?profile=vy` and `?profile=phong` each load the right profile.
- [ ] System prompt includes that child's profile + memory (memory empty first run).
- [ ] `profile_store` round-trips memory to/from `backend/profiles/<id>.json`.
- [ ] Unknown/missing profile id falls back safely (no crash) + logs a warning.
- [ ] `backend/profiles/` gitignored; no audio stored; no credential in files.
- [ ] Core loop still works (verified via the WS test client).

## Risk Assessment

- **Profile JSON committed by accident** → gitignore `backend/profiles/` up front;
  verify with `git status` before any commit.
- **Corrupt/missing memory file** → load returns "" and logs; never throws into
  the session path.
- **Config signature change breaks callers** → it's all backend-internal; update
  every caller in the same change; the WS test client proves it end to end.
