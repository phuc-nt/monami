---
title: 'Phase 0 Spike: Validate Gemini Live for Vietnamese 5yo Child Speech'
description: >-
  Throwaway 1-2 day spike to GO/NO-GO Architecture B (LiveKit + Gemini Live) by
  testing real VN 5yo child speech
status: in-progress
priority: P1
created: 2026-06-21T00:00:00.000Z
source: ../reports/brainstorm-260621-1409-bilingual-voice-companion-kids-report.md
---

# Phase 0 Spike: Validate Gemini Live for Vietnamese 5yo Child Speech

## Overview

**Single riskiest assumption gate.** Before building anything, prove (or disprove) that **Gemini Live native audio** can handle real Vietnamese 5-year-old speech — slow, hesitant, mispronounced, code-switching EN/VN — well enough to commit to **Architecture B** (Flutter + LiveKit + LiveKit Agents + Gemini Live). If it fails, pivot to **Architecture C** (Deepgram STT + Gemini Flash + ElevenLabs TTS).

**THROWAWAY spike, NOT production code.** Minimal harness only. Do NOT scaffold the Flutter app, Supabase schema, Rive, or LiveKit Cloud setup. Goal = measured numbers + a go/no-go decision, nothing more.

**Duration:** 1-2 days. **Cost:** a few USD of Gemini Live audio.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Setup Spike Harness](./phase-01-setup-spike-harness.md) | Completed |
| 2 | [Run Trials & Measure](./phase-02-run-trials-measure.md) | In Progress |
| 3 | [Decide Go-NoGo & Report](./phase-03-decide-go-nogo-report.md) | Pending |

## Acceptance Criteria (GO gate)

GO for Architecture B requires ALL of:
- Gemini Live correctly understands **≥~85%** of the kids' actual utterances (intent captured, not verbatim).
- **No obvious word-stealing / mid-sentence cutoff** of slow/hesitant child speech (risk: bug #2117).
- Perceived latency feels **natural** (target <~1.2s end-to-end VN→SG; measure actual).
- **EN↔VN code-switching** within a conversation is handled smoothly.
- Strict safety behavior stays **child-appropriate** (no scary/inappropriate output; graceful refusal + redirect on off-topic).

Any hard fail (esp. understanding <85% or systematic cutoff) → **NO-GO → pivot to Architecture C**, re-run a trimmed version of this spike against C.

## Dependencies

- Upstream: approved design `../reports/brainstorm-260621-1409-bilingual-voice-companion-kids-report.md`.
- Blocks: all later phases (Phase 1 voice loop onward) of the main project — they must not start until this gate passes.
- External: Google Cloud / Vertex AI project with Gemini Live access in `asia-southeast1`; billing enabled.

## Open Questions (resolve during spike, do NOT invent)

1. **Gemini model version:** exact native-audio model id — preview models deprecated 2026-03; pick latest stable native-audio model at spike time (confirm from Vertex AI docs, do not hardcode from memory).
2. **Harness path:** direct Gemini Live API call (simplest, fastest to truth) **vs** minimal Python LiveKit Agent harness (tests turn-detector tuning too). Recommendation in Phase 1 — start direct, add LiveKit only if cutoff is the deciding factor.
3. **Child voice samples — ethics:** how to capture/replay real child speech without retaining audio long-term (record locally, delete after scoring; no upload to any third-party store beyond the live API call).
