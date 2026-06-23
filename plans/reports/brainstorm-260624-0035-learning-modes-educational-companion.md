# Brainstorm: Learning Modes — Monami as an educational companion

**Date:** 2026-06-24
**Status:** Design approved → proceed to plan
**Context:** Next phase after the multi-child app shipped to TestFlight. Make
Monami support learning (English-first), beyond free chat.

## Problem statement

Monami already free-chats bilingually (VN/EN code-switch) — so it incidentally
"exposes" English already, no code needed. The user wants **structured** learning
support: English, plus storytelling + curious-science, as guided activities the
child can enter — while keeping the experience **voice-first** (no images this
phase).

## Key honest framing (from the debate)

- Monami's smart free-chat already does a lot of the "teaching." The real question
  was how much STRUCTURE to add — decided: **Level B** (structured learning modes),
  not Level A (prompt-only) or Level C (curriculum + progress tracking + dashboard).
- **Voice-first + visual math (numbers/colors/shapes) is a contradiction** for a
  5-year-old. Decision: **DROP math this phase** — do English + Storytelling +
  Science (all voice-friendly); math waits for a later phase with on-screen visuals.
- The heaviest cost is **authoring content**, not code. Decision: start with
  AI-generated content (user reviews), kept small + expandable.

## Decisions (locked via Q&A)

| Decision | Choice | Rejected |
|---|---|---|
| Depth | **Level B — structured learning modes** | A (prompt-only); C (progress tracking + parent dashboard) |
| Subjects (this phase) | **English + Storytelling + Science** | Math (deferred — needs visuals); full multi-subject at once |
| Experience | **Voice-first only** (robot face, no images) | On-screen images / visual aids |
| Where content lives | **Structured curriculum (JSON) the backend loads into the prompt** | Pure system-prompt; Gemini-improvises-everything |
| Entering a mode | **Mode buttons on the voice screen** (both child + parent can tap) | Bot self-suggests; parent-only toggle |
| Content authoring | **AI-generated initial content (user reviews)**, start small | Hand-author everything; minimal content + improvise |

## Target design

### 1. Modes
The voice screen gains a friendly mode selector (a few big buttons):
```
[ 💬 Trò chuyện ] [ 🔤 Học tiếng Anh ] [ 📖 Kể chuyện ] [ 🔬 Vì sao? ]
```
- **Trò chuyện** = today's free chat (unchanged; default).
- The 3 learning modes make the bot lead per that mode's script.
- Selecting a mode passes a `mode` param on connect (like the existing
  `device`/`profile` params) → backend loads that mode's prompt + content into the
  Gemini Live session. No change to the Gemini Live architecture — only the prompt
  builder.

### 2. Structured content (backend)
```
backend/curriculum/
  english.json    # topics: animals, food, family… (EN words + simple sentences)
  stories.json    # a few short stories (title, summary, characters)
  science.json    # common "why" topics + age-5 answers
```
Each mode has a **leading script** (how the bot opens, encourages, repeats for
retention) + a **content list**, starting **small (1–2 topics/subject)**, expanded
later. AI-generated first draft; user reviews for pedagogical fit. The backend picks
content (optionally informed by the child's memory — "did animals yesterday, food
today") and stuffs it into the session's system prompt.

### 3. Reuse existing memory (no new data model)
Extend the per-child text memory to also note **what topics the child has done**, so
the bot can revisit/advance. Stays a text summary (KISS) — NOT a learning data model
(that was Level C, rejected).

### 4. Don't touch what works
Voice loop, mic, robot face, guest, multi-child, gendered face — unchanged. Default
mode = free chat, so non-users behave exactly as today. Guest can enter modes too
(no progress saved).

## Scope OUT (deferred)

Math + any visual teaching; on-screen images; parent progress dashboard;
levels/grading; pronunciation scoring. (Math + visuals is the natural NEXT phase.)

## Implementation considerations / risks

- **Content authoring is the long pole**, not code. Mitigate: start with 1–2 topics
  per subject; AI-draft + user review; a clean JSON schema so adding topics is data,
  not code.
- **Prompt bloat / latency:** stuffing curriculum into the system prompt grows it —
  keep per-session content small (the chosen topic only), not the whole curriculum.
- **Mode UI for a 5-year-old:** buttons must be big, icon-led, few. A child might
  tap randomly — fine (modes are all safe); the bot adapts.
- **Memory schema drift:** adding "topics done" to the summary must stay backward
  compatible with existing child docs (the summarizer already free-form).
- **Backward compat:** `mode` param is optional → omitting it = free chat = today's
  behavior. Old app builds keep working.

## Success criteria

- Tapping "Học tiếng Anh" / "Kể chuyện" / "Vì sao?" makes the bot lead that activity
  in a clearly different, structured way (not generic chat).
- English mode teaches a small vocab set with repetition + encouragement; the child
  hears + repeats words.
- Content lives in JSON; adding a topic is editing data, not code.
- Memory notes the topic done; next session the bot can revisit/advance.
- Free chat + all existing features unchanged; default behavior identical to today.

## Open questions (resolve in plan)

1. Exact mode list + icons/labels (VN wording for a 5-year-old).
2. JSON schema shape for each subject (fields per topic).
3. How the backend selects "today's topic" (round-robin? memory-driven? simplest
   first).
4. Whether mode persists per child (remember last mode) or resets each session.

## Next step

→ `/mk:plan` for the Learning Modes phase (mode selector UI + `mode` param +
backend curriculum loader + 3 modes' content + memory "topics done").
