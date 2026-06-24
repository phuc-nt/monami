---
title: "Learning Modes — Educational Companion"
description: "Add structured, voice-first learning modes to Monami (English + Storytelling + Science) on top of the shipped multi-child app. A mode selector on the voice screen passes an OPTIONAL `mode` WS param; the backend loads a small JSON curriculum into the Gemini Live system prompt and notes 'topics done' in the existing per-child text memory. Default (no mode) = today's free chat, unchanged."
status: pending
priority: P2
created: 2026-06-24
blockedBy: [260623-1906-publish-prep-multi-child-per-device]
---

# Learning Modes — Educational Companion

## Overview

Monami already free-chats bilingually, so it incidentally exposes English. This
phase adds **structured learning modes** the child can enter from the voice
screen — **Học tiếng Anh / Kể chuyện / Vì sao?** — while staying **voice-first**
(no images) and **not touching the voice loop**. A mode is just an optional
`mode` query param on the WS connect; the backend swaps in a mode-specific system
prompt + a small piece of JSON curriculum. Free chat ("Trò chuyện") is the
default and is unchanged.

Design + decisions locked in the approved brainstorm:
`plans/reports/brainstorm-260624-0035-learning-modes-educational-companion.md`.

## Decided (from brainstorm)

- **Subjects this phase:** English + Storytelling + Science. **Math DROPPED**
  (needs on-screen visuals → a later phase).
- **Voice-first only.** Robot face unchanged.
- **Optional `mode` WS param** (alongside `device`/`profile`/`token`). Omitting it
  = free chat = today's behavior → **backward compatible**; old builds keep working.
- **NO Gemini Live architecture change** — only the system-prompt builder
  (`gemini_session_config.py`).
- **Content = small JSON curriculum** (`backend/curriculum/{english,stories,science}.json`),
  AI-drafted (user reviews), **start with 1–2 topics/subject**. Per session, stuff
  only the **chosen topic** into the prompt (not the whole curriculum).
- **Progress = extend the existing per-child TEXT memory** to note "topics done".
  NO new learning data model. Backward compatible with existing child docs.

## Phases

| Phase | Name | Status | Depends on |
|-------|------|--------|-----------|
| 1 | [Backend Mode Plumbing and Prompt Builder](./phase-01-backend-mode-plumbing-and-prompt-builder.md) | ✅ completed | — |
| 2 | [Curriculum Content and Topic Selection](./phase-02-curriculum-content-and-topic-selection.md) | ✅ completed | 1 |
| 3 | [App Mode Selector UI](./phase-03-app-mode-selector-ui.md) | ✅ completed | 1 |
| 4 | [Memory Topics-Done and Device Verification](./phase-04-memory-topics-done-and-device-verification.md) | pending | 2, 3 |

**Ordering:** 1 (the `mode` param + a mode-aware prompt seam with placeholder
content) lands the plumbing without UI. 2 (the real JSON curriculum + how a topic
is picked) and 3 (the app mode buttons) can proceed after 1 — different files
(2 is backend curriculum, 3 is app UI). 4 ties it together: memory remembers what
was learned, then a real-device pass.

## Acceptance criteria (whole plan)

- Tapping a learning mode makes the bot lead that activity in a clearly different,
  structured way (not generic chat); tapping "Trò chuyện" behaves exactly as today.
- The `mode` param is **optional** — an old build (no `mode`) and the macOS dev
  build behave identically to today (free chat). Verified.
- Adding a vocabulary word / story / science topic is **editing JSON**, not code.
- A learning session notes the topic in the child's memory; the next session the
  bot can revisit or move on.
- Voice loop, mic, robot face, guest, multi-child, gendered face — unchanged.
- Backend + app test suites stay green; verified on a real device against Cloud Run.

## Scope OUT

Math / any visual teaching; on-screen images; parent progress dashboard;
levels/grading; pronunciation scoring. (Math + visuals = the natural next phase.)

## Risks (plan-level)

- **Content authoring is the long pole, not code.** Keep the schema dead simple so
  topics are data; start with 1–2 topics/subject and expand later.
- **Prompt bloat / latency** if the whole curriculum is stuffed in. Mitigation:
  load only the chosen topic into the session prompt.
- **Backward compatibility is a hard requirement** — the `mode` param must be
  optional everywhere (backend default + app default), so nothing regresses for
  existing users / old builds.
- **Memory schema drift** — "topics done" must append to the free-form text summary
  without breaking existing child docs or the summarizer.

## Dependencies

Builds on the completed `260623-1906-publish-prep-multi-child-per-device` (the
device-scoped child store + memory + the WS param pattern this extends).
