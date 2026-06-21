---
type: phase0-go-nogo-decision
date: 2026-06-21
slug: gemini-live-vn-child-speech
status: decision
plan: ../260621-1409-phase0-spike-gemini-live-vn-child-speech/
decision: GO (Architecture B)
---

# Phase 0 GO/NO-GO — Gemini Live for VN 5yo Child Speech

> **DECISION: GO with Architecture B** (Flutter + LiveKit + LiveKit Agents +
> Gemini Live native audio). Validated with REAL child voices of both kids.

## Test setup

- Harness A (`spike/gemini_live_direct_probe.py`) → real Live API, us-central1.
- Real recordings of both children (~6.5s each), 48kHz stereo → 16kHz mono WAV.
- Model: `gemini-live-2.5-flash-native-audio`.

## Results (real child voices)

| Child | Question (actual) | Transcript correct? | Understood? | Latency (first audio) |
|-------|-------------------|---------------------|-------------|----------------------|
| Phong | "Tại sao xe ô tô lại có bốn bánh?" | ✅ exact | ✅ | **851–853 ms** |
| Vy | "Bà ơi tại sao phép thuật của Elsa lại có nhiều phép thuật?" | ✅ (after lang fix) | ✅ | **853 ms** |

- Both responses: warm, age-5 appropriate, bilingual-capable ("magic"), ended with
  an engaging follow-up question. Persona on target.
- **Latency ~850ms with real child voice — UNDER the <1.2s goal**, even VN→us-central1.
  (Earlier 1.25s smoke-test number was an artifact of a longer synthetic clip.)

## Gate evaluation

| Gate | Target | Result |
|------|--------|--------|
| Understanding | ≥85% | ✅ 2/2 understood correctly |
| No cutoff | no systematic cutoff | ✅ none observed (trailing-silence VAD) |
| Latency | feels natural, ~<1.2s | ✅ ~850ms |
| Code-switch EN/VN | smooth | ✅ kept "magic" naturally; needs more mixed-sentence trials |
| Safety | child-appropriate | ✅ both responses safe & warm |

→ All gates pass on this sample. **GO.**

## Key issue found & fixed: input-transcription language

- **Symptom:** Vy's real VN question was transcribed as Korean (`바보의.`) under
  auto-detect — though the model still *understood* it (answered about Elsa).
- **Root cause:** auto language detection on input transcription mis-fires on VN
  child speech. NOT a model-comprehension problem (model always understood).
- **Fix:** set `AudioTranscriptionConfig.language_hints =
  LanguageHints(language_codes=["vi-VN","en-US"])`. After fix, both kids
  transcribe correctly AND code-switching still works (hints guide, don't lock).
- Chose `language_hints` over `language_codes` (latter deprecated; hints keep
  EN/VN flexibility). Applied to the harness as the default.

### Benchmark: auto-detect vs hints, across models (3 runs/cell)

Probed available native-audio models first: ONLY two exist in us-central1 —
`gemini-live-2.5-flash-native-audio` (GA) and
`gemini-live-2.5-flash-preview-native-audio-09-2025` (old preview). No Gemini 3.x
native-audio Live model exists on Vertex AI yet.

| Model | Clip | auto-detect (VN ok) | hints [vi,en] (VN ok) |
|-------|------|---------------------|------------------------|
| 2.5-flash GA | Vy | **0/3** (→ Korean `바보의`) | **3/3** |
| 2.5-flash GA | Phong | 3/3 | 3/3 |
| 2.5-flash preview | Vy | **0/3** (→ Korean) | **3/3** |
| 2.5-flash preview | Phong | 3/3 | 3/3 |

- **Conclusion on the user's question:** specify the language (hints), do NOT rely
  on auto-detect. Auto-detect fails *consistently* (0/3) on Vy's voice on BOTH
  models — it's voice-dependent, not a model-version weakness, and there is no
  higher native-audio model to upgrade to. No "better" model needed —
  comprehension was never the issue; only the transcript label was. `language_hints`
  is 100% stable across models/voices and keeps bilingual flexibility. (Data-backed
  decision; revisit only if Google ships a new native-audio model.)

## Decisions confirmed

- **Region:** us-central1 (native-audio served only there; not Singapore/global).
  LiveKit agent/region planning must account for this; latency still fine (~850ms).
- **Model:** `gemini-live-2.5-flash-native-audio` — keep; no upgrade needed.
- **End-of-turn:** trailing silence + server VAD (NOT audio_stream_end).
- **Input transcription:** vi-VN + en-US hints, mandatory.

## Carry-forward to Architecture B Phase 1 (build)

- Use us-central1 for Gemini Live; co-locate LiveKit agent accordingly.
- Bake language_hints [vi-VN, en-US] into the agent's Live session config.
- Use trailing-silence/VAD turn handling; tune endpointing for slow kids.
- Per-child memory via system-prompt context-stuffing (KISS), set at session start.
- Spike harness can be deleted; keep this report + the working config snippets.

## Unresolved questions (de-risk during Phase 1, not blockers)

1. Code-switching on *mid-sentence* EN/VN mixes — only lightly tested; verify with
   more varied child utterances during Phase 1.
2. Cutoff behavior on genuinely slow/hesitant/pausing kids with long mid-utterance
   gaps — tune `END_SILENCE_MS` / endpointing if it clips them.
3. Latency under real flaky home wifi (these tests were on a stable connection).
4. Whether input-transcript (for the parent dashboard later) is reliable enough to
   show verbatim, or should be treated as best-effort.
