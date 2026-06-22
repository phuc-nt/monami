---
phase: 2
title: "Session Memory Summarization"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: [1]
---

> **Completed + live-validated (real GCP).** Two children (Vy/Phong); the right
> profile is loaded by `?profile=`; the session is summarized at teardown into
> `backend/profiles/<id>.json` and reloaded next session. Verified live: Phong's
> session produced a complete VN summary ("Phong hỏi tại sao xe ô tô có bốn
> bánh… Phong thích xe ô tô to.").
>
> **Two bugs found + fixed during the live test:**
> - Default summary model `gemini-2.0-flash-001` was retired on Vertex (memory
>   would silently never update) → switched to `gemini-2.5-flash`.
> - `gemini-2.5-flash` is a thinking model; `max_output_tokens=300` was consumed
>   by the thinking budget, truncating the summary mid-sentence. Fixed:
>   `thinking_config=ThinkingConfig(thinking_budget=0)` + raised the cap to 1024,
>   and added a `MAX_TOKENS` finish-reason guard that keeps the prior summary
>   rather than persisting a truncated one.

# Phase 2: Session Memory Summarization

## Overview

Make memory actually accumulate: collect the session's transcript, and at session
end ask a cheap text model to update the child's memory summary, then persist it.
Next session (Phase 1 already loads memory) the companion can refer back.

## Requirements

- Functional: during a session the backend keeps the running transcript (text the
  child said + the companion said — already available as transcripts). On session
  end, generate an updated short summary (merge prior summary + this session) and
  save it via `profile_store`. Empty/short sessions skip the update.
- Non-functional: summarization is best-effort and must NOT block or break session
  teardown (run it after the loop, guard failures). Summary stays short
  (≈3-5 sentences) and child-safe. Text only.

## Architecture

- Transcript capture: in `gemini_session.py`, accumulate `in_transcript` /
  `out_transcript` text into a per-session buffer as they're forwarded.
- New `backend/memory_summarizer.py`:
  - `summarize(prior_summary, transcript_text) -> str` using the google-genai
    client with a cheap TEXT model (NOT the live audio model) and a constrained,
    child-safe prompt: "Update what you remember about this 5-year-old. Keep it to
    a few warm, factual sentences; only use what was said; no speculation."
  - Returns the merged summary; on any error returns the prior summary unchanged.
- `run_session` teardown: after the pumps finish, if the transcript is non-trivial,
  call `summarize(load_memory(id), transcript)` and `save_memory(id, new_summary)`.
  Wrap in try/except + a short timeout; log and move on if it fails.

## Related Code Files

- Create: `backend/memory_summarizer.py` (one-shot text summary via google-genai)
- Modify: `backend/gemini_session.py` (accumulate transcript; summarize on end)
- Modify: `backend/profile_store.py` (only if a metadata field like `updated_at`
  needs adding — likely already there from Phase 1)
- Modify: `backend/README.md` (document the summarize-on-disconnect behavior)

## Implementation Steps

1. Resolve a current cheap text model id from the Vertex/google-genai client at
   impl time (don't hardcode a guessed id); confirm a one-shot `generate_content`
   works with the existing client.
2. `memory_summarizer.summarize`: build the child-safe prompt; call the text model;
   return merged summary; fall back to prior on error.
3. `gemini_session.py`: accumulate the transcript during the session.
4. On teardown: skip if transcript is empty/tiny; else summarize + save (guarded,
   best-effort, with a timeout so a slow/failed summary never hangs teardown).
5. Verify: run a session via the WS test client, disconnect, confirm
   `backend/profiles/<id>.json` summary updated; run again and confirm the new
   summary is loaded into the prompt (companion can reference the prior chat).

## Success Criteria

- [ ] After a real session, the child's stored summary reflects what was discussed.
- [ ] A following session loads that summary; the companion can refer back to it.
- [ ] Summarization failure/timeout does NOT break session teardown (graceful).
- [ ] Empty/near-empty sessions don't overwrite a good summary with nothing.
- [ ] Summary is short, child-safe, text-only; no audio retained.

## Risk Assessment

- **Summary call hangs teardown** → run guarded with a timeout, after the relay
  loop; never block the WS close on it.
- **Summary drifts/hallucinates** → constrain the prompt to "only what was said,
  a few sentences"; cap length; on doubt keep the prior summary.
- **Summary grows unbounded over many sessions** → instruct to MERGE/condense into
  a fixed short summary, not append; cap stored length.
- **Model id drift** → resolve a valid text model id at impl; fail safe (keep prior
  summary) if the call errors.
