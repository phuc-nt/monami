# Brainstorm — Data Model v2: Layered Memory + Curriculum-in-Firestore + Anonymous Stats

Date: 2026-06-25 · Status: agreed, ready to plan
Scope owner: phucnt · App: monami (bilingual kids voice companion, ages 4-10)

## Problem statement

Three asks, scoped down during brainstorm:

1. **Memory richer + longer-lived.** Today memory = ONE 800-char text blob
   (`memory.summary`) the model rewrites every session → old facts get overwritten,
   no long-term accumulation.
2. **Curriculum richer.** Today = static JSON files in repo (`english.json`,
   `science.json`), 4 topics each, loaded into the system prompt. Adding lessons
   needs an app/backend rebuild.
3. **Store more user data to analyze + optimize app.** ORIGINAL wording collided
   with the shipped privacy promise ("no analytics, no tracking, audio never
   stored" — in README + App Store privacy label + privacy policy). **Resolved:**
   user wants ANONYMOUS aggregate stats + technical-error diagnostics only — NO
   behavioral analytics, NO child content leaving the device as per-child analysis.
   Privacy promise stays intact; no App Store label change; no COPPA exposure.

UI/UX track (modernize look, iPad landscape) was explored separately via a live
on-device 3-skin playground (Dark+Depth / Glass / Clay) → **user kept the current
UI unchanged.** Out of scope here.

## Current state (scouted)

- Firestore: `devices/{device_id}/children/{child_id}` holding
  `{name, gender, age, interests[], created_at, memory:{summary, updated_at}}`.
- Parent device docs are PHANTOM (only subcollections); enumerate children via
  `collection_group("children")`, not `collection("devices").stream()`.
- Memory write path (`gemini_session.py` → `_update_memory` / `_with_done_notes`):
  the summarizer rewrites prose, but learning done-notes (`đã học: <mode>:<id>`)
  are carried forward DETERMINISTICALLY by code, not the model. **This is the
  precedent for "code-controlled persistent facts" — the layered design extends
  it, it is not new machinery.**
- Curriculum: `curriculum.py` loads JSON, renders ONE topic into the prompt;
  `load_topic` skips done topics via the done-notes in memory text.
- Dev/prod split via `FIRESTORE_PREFIX` (`dev_devices` vs `devices`), single
  `(default)` DB, project monami-kids-spike.
- App has NO local child cache — `ChildService.listChildren()` is a pure REST GET;
  what prod returns IS what the app shows.

## Agreed solution

### Principles
- **Backward-compatible, NO migration script.** Existing prod children must load
  unchanged. New schema = additive optional fields; missing field → empty default.
  Old docs self-upgrade as kids keep playing (facts get filled over time).
- **Code-controlled vs model-controlled split.** Durable data (facts, done topics)
  is merged by code (union, never overwrite); soft recap stays model-written.
  Extends the existing done-notes pattern.
- **Privacy unchanged.** No audio, no per-child conversation content in analytics.

### Part 1 — Layered memory + session journal (BUILD FIRST, highest value)

Replace the single `memory.summary` blob with:

```
devices/{device_id}/children/{child_id}
    ...profile...
    memory:
      facts:        { pets:[], friends:[], likes:[], dislikes:[] }   # durable, code-merged (union), never overwritten
      summary:      "soft recap of recent sessions"                   # model-written (as today)
      done_topics:  ["english:animals", "science:why-rain"]           # split OUT of the summary text
      updated_at:   ISO8601
    sessions/{session_id}:                                            # journal subcollection — WRITE ONLY this phase
      started_at, ended_at, mode, turn_count, summary_short
```

- End-of-session summarizer returns JSON: newly-observed `facts` + soft `summary`
  in ONE call. Code merges facts as a union (same spirit as `_with_done_notes`).
- Prompt build: durable facts + recent summary → model always recalls
  "your cat is named Mướp" even 50 sessions later.
- `sessions/` is WRITE-ONLY now (data for a future parent dashboard — no UI this
  round, confirmed YAGNI).
- Migration: old doc with text `memory.summary` still reads (facts empty,
  done_topics parsed from the old text's `đã học:` lines). No forced script.

### Part 2 — Curriculum → Firestore

```
curriculum/{mode}/topics/{topic_id}     # mode = english | science
    title_vi, words[], sentence_en/vi, predict_vi, follow_up_vi, order, enabled, age_band
```

- Backend reads Firestore, caches in-memory (curriculum changes rarely; load once
  per cold-start or short TTL).
- Seed script pushes the current 8 JSON topics to Firestore, IDs preserved (so
  existing done-notes keep matching).
- Fallback: Firestore error → read the bundled JSON (kept in repo as backup) → a
  mode never dies.
- Payoff: add a lesson = add a Firestore doc. No app rebuild, no backend deploy.

### Part 3 — Anonymous aggregate stats + error diagnostics

```
analytics/daily/{YYYY-MM-DD}            # aggregate counters, NEVER tied to a child
    sessions_total, by_mode:{chat,english,science},
    topics_completed:{...}, errors:{type: count}
```

- Increment anonymous counters at session end: +1 session, +1 for the mode, +1
  per topic done. NO child_id, NO conversation content.
- Diagnostics: count technical errors (session error, summary timeout, Firestore
  fail) into `errors:{type:count}` — the `logger.warning` sites already exist;
  add ONE counting hook.
- This is COUNTING, not behavioral tracking → no App Store label change, no COPPA.

## Build order (one plan, phased)

1. Part 1 (layered memory + journal) — highest value, touches the core loop.
2. Part 2 (curriculum → Firestore) — independent, additive.
3. Part 3 (anonymous stats + diagnostics) — thin, hooks existing seams.

Each phase verifies independently (unit + ws_test_client). All three share
Firestore, so one plan is right (vs three brainstorm→plan→cook cycles).

## Risks / mitigations

- **Overwriting prod memory** → additive schema + backward-compat read + NO
  migration script. Old docs untouched until the child next plays.
- **Prompt bloat from facts** → cap facts (small lists), keep summary short; the
  prompt only grows by a few bilingual lines.
- **Firestore curriculum outage** → bundled-JSON fallback keeps modes alive.
- **Summarizer returning malformed JSON** → best-effort contract already in place
  (`summarize` returns prior on any failure); JSON parse failure = keep prior.
- **Guest invariant** → unchanged: guests persist NOTHING (facts/sessions/stats
  all gated behind the existing `persist` flag). Stats counters are the only
  guest-allowed write IF we choose to count guest sessions — decision deferred to
  plan (default: count guest sessions in aggregate too, since it's anonymous).

## Out of scope (deferred)

- Parent dashboard UI (reads the `sessions/` journal) — separate plan.
- UI/UX modernization — user kept current look.
- Behavioral analytics / per-child telemetry — explicitly rejected (privacy).
- Age-variant curriculum CONTENT — model self-adjusts from `age`.
- Pronunciation scoring, images, Android.

## Unresolved questions (for the plan / validate step)

1. Facts schema: fixed keys (`pets/friends/likes/dislikes`) vs an open
   `{key: [values]}` map? Fixed is simpler + safer for prompt rendering;
   open is more flexible. Lean fixed (YAGNI).
2. Count GUEST sessions in `analytics/daily` aggregates? (Anonymous either way.)
   Lean yes — it's a pure count, useful for "how many quick-play sessions".
3. Curriculum cache invalidation: load-once-per-cold-start vs short TTL? Cold-start
   is simplest (Cloud Run scales to zero anyway → frequent fresh loads). Lean
   cold-start, no TTL.
4. `session_id` source: server-generated UUID vs derived from connection. Lean
   server UUID at session open.
```
