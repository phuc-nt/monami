# Learning Modes — phase 2: curriculum content + topic selection

**Date:** 2026-06-24
**Plan:** `plans/260624-0035-learning-modes-educational-companion/` (phase 2 of 4)

## Goal

Fill the phase-1 `lesson` seam with real, small content from a JSON curriculum, so
a learning mode leads a concrete topic — English vocab, a short story, or a
curious-science "why" — without bloating the prompt or touching free chat.

## What shipped

- `backend/curriculum/{english,stories,science}.json` — small AI-drafted content
  (1–2 topics each), bilingual VN/EN, age-5, safe. Schemas are minimal so adding a
  topic is editing JSON, not code.
- `backend/curriculum.py` — loads + caches the files; `load_topic(mode,
  memory_text)` picks the first not-yet-done topic (else the first), `None` for
  free chat / missing file; `render_lesson(mode, topic)` emits a compact bilingual
  block for ONE topic, capped at 800 chars. Defensive: missing/malformed/non-list
  JSON or an id-less topic → degrade to no lesson (the mode still runs on its
  leading script), never a crash.
- `gemini_session.run_session` now, for a learning mode, loads + renders the topic
  and passes it as the `lesson` arg. Free chat (mode=None) → `load_topic` None →
  `render_lesson` "" → prompt unchanged.

## The invariant held + a matching fix

Free chat stays byte-identical (phase-1 tests still pass) — double-gated: no topic
→ "" lesson, and `build_system_prompt` only appends the lesson inside the
`if script:` block (empty for free chat). Code review flagged a real
topic-selection bug: `topic_id in memory_text` could falsely "skip" a topic if the
memory summary merely contained that word (e.g. "animals"). Fixed by anchoring on
an exported `DONE_MARKER` ("đã học:") — `_topic_done` now matches only the
structured `"đã học: <mode>:<id>"` note. This also pins the exact format phase 4's
summarizer must write (shared constant → no space-mismatch).

## Content review (user-approved fixes)

Reviewer + user pass on the drafted content: science "why is the sky blue" reworded
from "spreads out" toward "tán ra/tán xạ" (scattering) for accuracy; English sample
sentence "I like apple." → "I like apples." (correct grammar). The rest (stories,
the rest of the words/questions) approved as age-appropriate and safe.

## Verification + review

- 10 curriculum tests + 40/40 full backend suite; smoke: english mode renders the
  animals lesson into the prompt; free chat renders nothing.
- Code review: safe, all 6 criteria met, no blockers; the `_topic_done` tighten was
  applied here (not deferred) since it also fixes the phase-4 write contract.

## State

Phase 2 done. Next: phase 3 (app mode-selector UI — the buttons that send `?mode=`),
phase 4 (summarizer writes the `DONE_MARKER` note + a real-device pass). Content is
data: adding topics later is a JSON edit.
