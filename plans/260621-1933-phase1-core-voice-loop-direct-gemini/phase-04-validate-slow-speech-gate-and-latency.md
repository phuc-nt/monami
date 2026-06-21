---
phase: 4
title: "Validate Slow-Speech Gate and Latency"
status: pending
priority: P1
effort: "0.5d"
dependencies: [3]
---

# Phase 4: Validate Slow-Speech Gate and Latency

## Overview

Decision-grade validation: (a) does Gemini's VAD cut off a slow/hesitant child —
the gate that decides whether LiveKit is needed later; (b) measure real end-to-end
latency on the full loop. Produce a short report.

## Requirements

- Functional: run slow/hesitant speech through the real loop and record whether the
  bot interrupts; measure first-audio + complete latency over several turns.
- Non-functional: results are decision-grade (enough samples, real conditions),
  written down for the LiveKit go/no-go.

## Architecture

- No new components. Use the integrated Phase 3 loop.
- Slow-speech inputs: <!-- Updated: Validation Session 1 - reuse Phase 0 clips, caveat -->
  decision = reuse Phase 0 clips (Vy/Phong) for the latency baseline. **Caveat:** those
  clips are fairly fluent and do NOT exercise long mid-sentence pauses, so the LiveKit
  cutoff gate is INCONCLUSIVE on them alone. If a firm LiveKit go/no-go is needed,
  record a pause-heavy clip ("Con muốn… ưmm… kể chuyện…") — keep audio local, delete
  after scoring. Otherwise report the gate as "not yet exercised; revisit if cutoffs
  observed in real use."
- Latency: read from backend timestamps (reuse the spike's measurement approach:
  t_user_end → t_first_audio → t_complete).

## Related Code Files

- Create: `plans/reports/phase1-validation-slow-speech-and-latency-report.md` (deliverable)
- Modify (if needed): `backend/gemini_session.py` (add latency timestamp logging if
  not already emitted to the client/log)

## Implementation Steps

1. Latency: run several normal-speed turns; record median + worst first-audio and
   complete latency on the real Flutter↔backend↔Gemini loop. Compare to the <1.2s target.
2. Slow-speech gate: feed 5-8 slow/hesitant utterances with long mid-sentence pauses.
   For each, note: did the bot start talking before the child finished? (Y=bad).
3. If cutoffs occur: try raising `END_SILENCE_MS`; re-test. Record whether tuning
   alone fixes it, or whether it needs semantic turn detection (→ LiveKit evidence).
4. Write the report: latency numbers, slow-speech cutoff results, and a clear
   recommendation: "Gemini VAD sufficient" OR "needs LiveKit turn-detector" with data.
5. Delete raw child audio; keep only scores + report.

## Success Criteria

- [ ] Real-loop latency measured (median + worst) vs <1.2s target.
- [ ] Slow/hesitant speech tested; cutoff behavior recorded.
- [ ] Clear data-backed recommendation on LiveKit (needed or not) for later phases.
- [ ] Report written to `plans/reports/`; raw child audio deleted.

## Risk Assessment

- **Small sample → noisy** → use enough utterances (≥5-8 slow ones); report as indicative.
- **Tuning END_SILENCE_MS trades latency vs cutoff** → if higher silence fixes cutoff
  but adds latency, document the trade so the LiveKit decision is informed.
- **Bias toward "no LiveKit"** (it's the cheaper path) → judge strictly on whether kids
  get cut off; if they do and tuning can't fix it, that's real LiveKit evidence.
