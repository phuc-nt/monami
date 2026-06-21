# 2026-06-21 — Phase 0 Spike: Gemini Live for VN Child Speech

**Decision: GO with Architecture B** (Flutter + LiveKit + LiveKit Agents + Gemini Live native audio + Supabase). Validated with real voices of both kids (Phong, Vy).

## What happened

Goal: de-risk the single riskiest assumption before building — does Gemini Live native-audio understand real Vietnamese 5yo speech well enough? Built a throwaway probe harness (`spike/gemini_live_direct_probe.py`), pushed both kids' real recordings through the live API, measured.

All gates passed:
- Understanding: 2/2 correct (Phong: "tại sao xe ô tô có 4 bánh"; Vy: "tại sao Elsa có nhiều phép thuật").
- Latency: ~850ms first-audio VN→us-central1 — under the <1.2s target.
- Responses: warm, age-5 appropriate, bilingual-capable, with engaging follow-ups.

## Findings (verified live, not assumed)

1. **Region:** native-audio model served ONLY in `us-central1`. NOT asia-southeast1/Singapore (brief's co-locate assumption invalid), NOT global. Latency still fine despite VN→US distance (~850ms with real child voice).

2. **Bug — `audio_stream_end=True` ignored** by the native-audio model → returns nothing, `receive()` hangs forever. Fix: append trailing silence + let server-side VAD detect end-of-turn (`END_SILENCE_MS`, default 800ms). This is THE end-of-turn mechanism for this model.

3. **Bug — input-transcription auto-detect mis-hears VN child speech.** Vy's Vietnamese transcribed as Korean (`바보의`) — though the model still understood and answered correctly. Fix: `AudioTranscriptionConfig.language_hints=["vi-VN","en-US"]`. Benchmarked auto vs hints 3×/cell across both available models (2.5-flash GA + old preview): auto-detect fails **0/3 on Vy consistently on BOTH models**; hints **3/3 stable**. Only two native-audio models exist on Vertex (both 2.5-flash) — no Gemini 3.x native-audio to "upgrade" to. → Specify language via hints, don't auto-detect. Voice-dependent, not a model-version weakness.

4. **Comprehension was never the issue** — only the transcript label. Model answered correctly even when the displayed transcript was wrong. Implication: input-transcript is best-effort for a future parent dashboard, not authoritative.

## Carry-forward to Phase 1 (build)

- Region: `us-central1`; co-locate LiveKit agent accordingly.
- Model: `gemini-live-2.5-flash-native-audio` (keep; no upgrade needed/available).
- `language_hints=["vi-VN","en-US"]` — mandatory in the agent's Live session config.
- Turn handling: trailing-silence + VAD (NOT audio_stream_end); tune endpointing for slow kids.
- Per-child memory: system-prompt context-stuffing at session start (KISS), not RAG.

## Artifacts

- Spike harness: `spike/` (throwaway — delete when Phase 1 stable).
- GO/NO-GO report: `plans/reports/phase0-go-nogo-decision-gemini-live-vn-child-speech-report.md`.
- Plan: `plans/260621-1409-phase0-spike-gemini-live-vn-child-speech/` — 100% complete.

## Open (de-risk in Phase 1, not blockers)

- Mid-sentence EN/VN code-switching — only lightly tested.
- Cutoff behavior on genuinely slow/hesitant kids (tune `END_SILENCE_MS`).
- Latency on real flaky home wifi (tests were on stable connection).
