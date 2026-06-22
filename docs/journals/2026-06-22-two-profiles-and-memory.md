# Two Profiles and Memory

**Date:** 2026-06-22
**Plan:** `plans/260622-2119-two-profiles-and-memory/` (3 phases, all done)

## Goal

Turn the single hard-coded "Vy" companion into two children (Vy + Phong) the
companion remembers between sessions — pick a child in the app, the backend loads
that child's profile + a memory summary, and writes a fresh summary at session end.

## What shipped

**Backend (Phases 1-2):**
- `child_profile.py` — `PROFILES` registry (vy, phong) + `get_profile` with safe
  fallback (unknown/None → vy + a logged warning).
- `profile_store.py` — local JSON per child (`backend/profiles/<id>.json`), text
  only, path-traversal-guarded, tolerant of missing/corrupt files. Gitignored.
- `gemini_session_config.py` — `build_system_prompt(profile, memory)` /
  `build_live_connect_config(...)` take the selected child + their memory; memory
  block only added when non-empty (first session = profile only).
- `main.py` — reads `?profile=<id>` from the WS connect URL.
- `gemini_session.py` — `run_session(ws, profile_id)` resolves profile + loads
  memory; `_downlink` accumulates the transcript; on teardown `_update_memory`
  summarizes the session into the child's memory (best-effort, bounded timeout).
- `memory_summarizer.py` — one-shot text-model summary (NOT the live audio model),
  child-safe constrained prompt, returns prior summary on any failure.

**Client (Phase 3):**
- `profile_picker.dart` — first screen: two tappable cards (Vy/Phong) with a
  happy robot face tinted per child. Tapping opens the voice screen for that child.
- `main.dart` — home is the picker → `VoiceHome(child)`; back arrow ends the
  session (→ backend summarizes). Robot face tinted per child.
- `voice_controller.dart` — ctor now `required profileId` → `?profile=<id>` URL.

## Decisions

- **Pick in-app** (not voice-ID / not behind a PIN) — a tap picker is simplest and
  kid-usable; PIN is a separate later phase.
- **Local JSON storage** (not Supabase) — YAGNI for 2 kids; the store is a thin
  module so swapping to a DB later is small.
- **AI-generated rolling summary** (not just fixed profile, not full transcript) —
  a few warm factual sentences merged each session; small, privacy-light.

## Live validation (real GCP) + two bugs found

Ran Phong's clip through the loop several times, disconnected, checked
`profiles/phong.json`. The companion greeted Phong + referenced his interests, and
memory accumulated: *"Phong hỏi tại sao xe ô tô có bốn bánh… Phong thích xe ô tô to."*

Two bugs surfaced only under real GCP (the fake-client test couldn't catch them):
1. **Default summary model `gemini-2.0-flash-001` was retired on Vertex** (≈2026-06)
   → `summarize()` caught the error and kept prior, so memory silently never
   updated. Switched to `gemini-2.5-flash`; added `MEMORY_SUMMARY_MODEL` to
   `.env.example`.
2. **Truncated summaries.** `gemini-2.5-flash` is a thinking model; the thinking
   budget ate the 300-token output cap, cutting the note mid-sentence ("Phong tò").
   Fixed: `thinking_config=ThinkingConfig(thinking_budget=0)` + raised the cap to
   1024 + a `MAX_TOKENS` finish-reason guard that keeps the prior summary instead
   of persisting a truncated one. Re-test produced complete summaries.

## Code review fixes (before live test / before commit)

- Backend: the two model bugs above (H1 model id; thinking/token truncation).
- Client: a fast double-tap on a child card would push `VoiceHome` twice → two
  live sessions/sockets/mic grabs (very likely with a 5-year-old). Guarded with
  `Navigator.canPop()`.

## Privacy

Per-child memory (`backend/profiles/`) holds a name + chat summaries → gitignored,
never committed, text only (no audio). Verified via `git check-ignore` and that no
`profiles/*.json` was ever staged. The summary call never touches the client; the
credential stays server-side (ADC).

## State

- 2 profiles + memory: **done** — backend live-validated; picker built + verified.
- Remaining for the app: parental PIN + time limit; cloud deploy; iPad/mobile polish.

## Carry-forward / open

- Live "pick Vy vs Phong in the app and each is remembered" end-to-end is a user
  run step (needs mic): pick a child, talk, switch child, confirm the right name +
  recall per child.
- Memory summary uses `gemini-2.5-flash` in `us-central1` — if that changes,
  override `MEMORY_SUMMARY_MODEL`.
- The picker keeps its two `RobotFace` controllers mounted under `VoiceHome`
  (constant, not a leak); fine at this scale.
