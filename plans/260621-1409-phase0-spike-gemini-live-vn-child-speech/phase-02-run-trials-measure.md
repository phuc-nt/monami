---
phase: 2
title: Run Trials & Measure
status: completed
priority: P1
effort: 0.5-1d
dependencies:
  - 1
---

# Phase 2: Run Trials & Measure

## Overview

Run a structured set of trials with **real 5yo voices** through the harness and record measured numbers for the five gate metrics: understanding, cutoff, latency, code-switching, safety.

## Requirements

- Functional: a repeatable trial script (list of utterances/scenarios) covering the hard cases; scored results logged.
- Non-functional: trials run on real home wifi in Vietnam (not idealized network); both kids if feasible.

## Architecture

Five metric tracks, scored from the JSONL logs + listening to output audio:

1. **Understanding (≥85% target):** % of child utterances where Gemini captured the intent. Include deliberately hard cases — slow, hesitant ("ưmm…"), mispronounced, low-volume.
2. **Cutoff (#2117):** count utterances where the model spoke before the child finished. Test with slow/pausing speech specifically. If frequent on harness A → re-run subset on harness B with `min_endpointing_delay` 1.2-1.5s and re-count.
3. **Latency:** from JSONL stamps — `t_first_audio - t_user_end` (responsiveness) and `t_complete - t_user_end`. Report median + worst-case; flag any 5-6s spikes.
4. **Code-switching:** scenarios that start VN then switch to EN mid-conversation, and a mid-sentence mix; score whether responses stay natural and don't break.
5. **Safety:** probe a few age-appropriate "tại sao" questions + 2-3 gently off-topic/edgy prompts; confirm strict safety keeps output child-appropriate with graceful redirect, no scary content.

## Related Code Files

- Create: `spike/trial_scenarios.md` (the fixed list of utterances/scenarios per track — so trials are repeatable and comparable A vs B vs C)
- Create: `spike/results/trial_log.jsonl` (raw per-utterance logs)
- Create: `spike/results/scoring_sheet.md` (human scoring: understood y/n, cutoff y/n, latency ms, codeswitch ok y/n, safety ok y/n)
- Modify: harness scripts only if a logging gap surfaces.

## Implementation Steps

1. Write `trial_scenarios.md`: ~15-25 utterances spread across the 5 tracks, weighted toward the hard understanding + cutoff cases (that's where B fails if it fails).
2. Run trials with real child voice(s); keep sessions short (kids' attention) — multiple short runs are fine.
3. Capture latency from logs; listen back to output audio to score understanding/cutoff/codeswitch/safety into `scoring_sheet.md`.
4. If cutoff is a problem on A, run the cutoff subset on harness B with tuned endpointing; record whether it resolves.
5. Tally per-track results; note qualitative observations (does it feel like a friend? tone warm? does it talk too fast for a 5yo?).
6. Delete raw child audio after scoring (retain only the text scoring sheet + numbers).

## Success Criteria

- [ ] All 5 tracks exercised with real child voice on real VN home network.
- [ ] Understanding % computed against the ≥85% gate.
- [ ] Cutoff frequency counted (A, and B if escalated).
- [ ] Latency median + worst-case recorded.
- [ ] Code-switching and safety scored pass/fail with notes.
- [ ] Raw child audio deleted; only text scores retained.

## Risk Assessment

- **Small sample → noisy %** → keep ≥15-20 utterances; report as indicative, not statistical proof.
- **Kid won't cooperate / short attention** → split into short sessions; pre-record some samples as backup.
- **Network variance skews latency** → run a few passes; report median + worst, note conditions.
- **Scoring subjectivity** → simple binary per utterance + a second listener (the parent) where possible.
