---
phase: 1
title: "Backend Mode Plumbing and Prompt Builder"
status: completed
priority: P2
effort: "0.5d"
dependencies: []
---

# Phase 1: Backend Mode Plumbing and Prompt Builder

## Overview

Thread an OPTIONAL `mode` through the WS connect into the system-prompt builder,
so a session can be a learning mode instead of free chat — without touching the
Gemini Live architecture or breaking existing (mode-less) sessions.

## Requirements

- Functional:
  - `GET /ws/voice?…&mode=<mode>` accepts an optional `mode` query param. Valid
    modes: `english`, `stories`, `science` (the 3 learning modes). Any other value
    or absence → **free chat** (today's behavior).
  - `run_session` receives the mode and threads it to the config builder.
  - `gemini_session_config.build_system_prompt(profile, memory_text, mode=None, lesson=None)`:
    when `mode` is a learning mode, prepend/append a **mode-specific leading
    script** (how the bot opens, encourages, repeats for retention) + a `lesson`
    block (the chosen topic's content — a placeholder string in this phase; real
    content comes from phase 2's curriculum loader). When `mode` is None/unknown →
    exactly the current prompt (unchanged).
- Non-functional:
  - **Backward compatible (hard req):** no `mode` → byte-identical behavior to
    today. Old app builds + the macOS dev build keep working.
  - Mode validation is centralized (one `VALID_MODES`/enum), so the app + backend
    agree on the strings.
  - Keep the Gemini Live config (audio, safety, language hints) unchanged.

## Architecture

- New `backend/learning_modes.py`: a `Mode` enum/constants (`english`, `stories`,
  `science`) + `parse_mode(raw) -> str | None` (None for free chat) + per-mode
  **leading-script** text (the pedagogy framing). Keeps mode logic in one file.
- `main.py`: read `mode = websocket.query_params.get("mode")`; pass into
  `run_session(...)`. (Guest + any child can use a mode.)
- `gemini_session.py`: `run_session(ws, device_id, child_id, is_guest, mode=None)`;
  pass `mode` into the config build.
- `gemini_session_config.py`: `build_system_prompt(...)` + `build_live_connect_config(...)`
  gain an optional `mode` (+ later `lesson`) and compose the mode script when set.
  This is the ONLY behavioral seam.

## Related Code Files

- Create: `backend/learning_modes.py`.
- Modify: `backend/main.py`, `backend/gemini_session.py`,
  `backend/gemini_session_config.py`.
- Create (tests): `backend/tests/test_learning_modes.py`.

## Implementation Steps

1. `learning_modes.py`: define `VALID_MODES = {"english","stories","science"}`,
   `parse_mode()`, and a `leading_script(mode)` returning the per-mode pedagogy
   framing (short, bilingual, age-5).
2. `gemini_session_config.build_system_prompt(profile, memory_text, mode=None, lesson=None)`:
   if `parse_mode(mode)` is set, compose persona + child profile + memory + **mode
   script + lesson**; else the current prompt verbatim. Thread `mode`+`lesson`
   through `build_live_connect_config`.
3. `gemini_session.run_session(..., mode=None)`: pass `mode` (lesson stays None
   this phase — placeholder) to the builder.
4. `main.py`: read the `mode` query param, pass to `run_session`.
5. Tests: prompt builder with each mode includes its script; no mode → prompt
   equals the legacy prompt (snapshot/contains check); `parse_mode` maps unknown →
   None.

## Success Criteria

- [ ] WS with `?mode=english|stories|science` runs a session whose system prompt
      contains that mode's leading script.
- [ ] WS with no `mode` (or a bad value) produces the **current** prompt unchanged
      (proven by test) — free chat behavior is byte-identical.
- [ ] Guest + registered child can both use a mode.
- [ ] Gemini Live config (audio/safety/hints) unchanged; existing backend tests
      still pass; new mode tests pass.

## Risk Assessment

- **Regressing free chat** — the no-mode path must be the exact old prompt. Mitigate
  with a test asserting the mode-less prompt is unchanged.
- **Mode string drift app↔backend** — one source of truth (`VALID_MODES`); the app
  must use the same strings (phase 3 references these).
- **Lesson is a placeholder here** — real content lands in phase 2; keep the
  `lesson` param wired so phase 2 only fills the loader.
- **Rollback:** the `mode` param is additive + optional; ignoring it restores
  today's behavior with zero app changes.
