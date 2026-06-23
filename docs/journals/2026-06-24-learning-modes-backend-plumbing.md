# Learning Modes — phase 1: backend mode plumbing

**Date:** 2026-06-24
**Plan:** `plans/260624-0035-learning-modes-educational-companion/` (phase 1 of 4)

## Goal

Lay the backend seam for structured learning modes (English / Storytelling /
Science) without touching the voice loop or regressing free chat — the first slice
of turning Monami into an educational companion.

## What shipped

- `learning_modes.py` (new) — the single source of truth: `VALID_MODES`
  (`english`/`stories`/`science`), `parse_mode(raw)` (None = free chat for
  absent/empty/"chat"/unknown), and a per-mode bilingual `leading_script` (the
  pedagogy framing). The Flutter app will mirror these strings.
- `gemini_session_config.build_system_prompt(profile, memory_text, mode=None,
  lesson="")` — appends the mode's leading script + an optional lesson block ONLY
  when a learning mode is active; with no mode the prompt is byte-identical to
  before. `build_live_connect_config` threads the same optional `mode`/`lesson`;
  audio/safety/language-hints unchanged.
- `gemini_session.run_session(..., mode=None)` + `main.py` reads an optional
  `?mode=` WS param and passes it through. Lesson stays empty this phase (the
  curriculum loader is phase 2) — a mode runs on its leading script alone.

## The invariant that mattered

**Free chat must not regress.** With no mode (or an unknown one like the deferred
"math"), the system prompt is exactly the old persona + profile + memory. Proven
by `test_no_mode_prompt_is_unchanged` (real `==`, not a contains check) + a
drift-proof backstop asserting the free-chat prompt contains none of the mode
scripts / lesson header. The `if script:` guard nests both the script and the
lesson block, so a `lesson` passed without a mode cannot leak.

## Verification + review

- 6 new tests + 30/30 full backend suite; manual smoke (connect `?mode=english`,
  prompt shows the English script + lesson; logs show `mode=english`).
- Code review: safe, all 6 criteria met, no must-fix. Even prompt-injection via
  the `mode` param is neutralized by the exact-match allowlist. Applied the two
  non-blocking suggestions: hoisted the `learning_modes` import to module top, and
  added the drift-proof no-mode-markers test.

## State

Phase 1 done. Next: phase 2 (real JSON curriculum + topic selection), phase 3 (app
mode-selector UI), phase 4 (memory "topics done" + device verify). The `lesson`
seam is wired + guarded, so phase 2 only needs to populate it. Backward compat
(optional `mode`) is a hard requirement carried through all phases.
