---
title: "Two Profiles and Memory"
description: "Per-child profiles (Vy + Phong) with persisted memory: pick a child in the app, the backend loads that child's profile + an AI-generated memory summary into the system prompt, and writes a fresh summary at session end. Local JSON storage."
status: completed
priority: P2
created: 2026-06-22
blockedBy: [260621-1933-phase1-core-voice-loop-direct-gemini]
---

# Two Profiles and Memory

## Overview

Turn the single hard-coded "Vy" profile into **two real children (Vy + Phong)**
the companion remembers between sessions. The child is chosen in the app; the
backend loads that child's profile + a short memory summary into the system
prompt; at the end of a session the backend asks a cheap text model to summarize
what happened and saves it, so the next session feels continuous.

Personalization was a top-3 priority from the original brainstorm; this delivers
the "remembers each kid" experience.

## Decided design

- **Child selection:** a picker screen in the app (tap Vy or Phong). The client
  passes the chosen `profile_id` to the backend on connect (WS query param).
- **Storage:** local JSON on the backend, one file per child
  (`backend/profiles/<id>.json`) — profile facts + the latest memory summary +
  (optional) recent transcript. No DB/cloud (YAGNI for 2 kids); the storage layer
  is a thin module so swapping to Supabase later is a small change.
- **Memory:** fixed profile (name/age/interests) + an **AI-generated summary** of
  past sessions. At session end the backend summarizes that session's transcript
  (a cheap one-shot text call) and folds it into the stored summary; next session
  loads it into the system prompt. Keep the summary short (a few sentences) so the
  prompt stays small.

## Architecture (where it hooks in)

```
Flutter: ProfilePicker screen → chosen id → VoiceController(profileId)
   → VoiceSocket connects ws://…/ws/voice?profile=<id>
Backend: /ws/voice reads ?profile → run_session(ws, profile_id)
   → load profile + memory (profile_store) → build_live_connect_config(profile, memory)
   → … conversation … → on session end: summarize transcript → profile_store.save
```

Current touchpoints (from scout):
- `backend/child_profile.py` — single `DEFAULT_PROFILE`; becomes a registry of 2.
- `backend/gemini_session_config.py:build_system_prompt()` / `build_live_connect_config()`
  — hard-codes `DEFAULT_PROFILE`; must take a selected profile + memory text.
- `backend/gemini_session.py:run_session(ws)` — gains a `profile_id`; collects the
  transcript; triggers summarization on teardown.
- `backend/main.py` `/ws/voice` — reads the `profile` query param.
- `app/lib/voice_controller.dart` / `voice_socket.dart` — pass the profile id in
  the WS URL.
- `app/lib/main.dart` — show the picker before the voice screen.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Backend Profiles And Storage](./phase-01-backend-profiles-and-storage.md) | ✅ Completed |
| 2 | [Session Memory Summarization](./phase-02-session-memory-summarization.md) | ✅ Completed (live-validated) |
| 3 | [Flutter Profile Picker](./phase-03-flutter-profile-picker.md) | ✅ Completed |

## Acceptance criteria (whole plan)

- Two children exist (Vy + Phong); each has a distinct profile.
- The app lets you pick which child; the backend uses that child's profile +
  memory for the session (greets the right name, references their interests).
- At session end a memory summary is generated and persisted per child.
- A new session for that child loads the prior summary → the companion can refer
  back to something from before.
- Storage stays local (JSON), credential-free, and child audio is never stored.
- No regression to the core voice loop / robot face.

## Scope OUT (later)

Parental PIN gating the picker; time limits; Supabase/cloud sync; editing
profiles in-app; long-term transcript retention/search; multi-device sync;
embeddings/RAG memory.

## Privacy / safety

- Store TEXT only (profile, summary, optionally transcript text) — never audio.
- The JSON files contain a child's name + interests + chat summaries → treat as
  private: gitignore `backend/profiles/`, never commit. (Profiles are local data,
  not code.)
- Summarization prompt must stay child-safe and only summarize, not invent.

## Dependencies

- Blocked by (satisfied): core voice loop (profile/config/session entry exist).
- Uses the same Gemini/Vertex creds the backend already has (for the summary call).
- No new packages expected (stdlib `json` + the existing google-genai client).

## Open questions (resolve during execution)

1. Summary model: reuse google-genai with a cheap text model (e.g. a flash text
   model) for the end-of-session summary — confirm an available model id at impl.
2. When exactly to summarize: on WS disconnect (simplest) vs an explicit "end"
   signal. Default: on disconnect, best-effort (don't block teardown).
3. Transcript retention: keep the last session's transcript in the JSON for
   context, or only the rolling summary? Default: rolling summary only (smaller,
   privacy-lighter); revisit if recall feels thin.
