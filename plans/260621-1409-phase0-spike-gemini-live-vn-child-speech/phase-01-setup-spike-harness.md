---
phase: 1
title: Setup Spike Harness
status: completed
priority: P1
effort: 0.5d
dependencies: []
---

# Phase 1: Setup Spike Harness

## Overview

Stand up the minimal harness to push real child voice through Gemini Live native audio (Vertex AI, `asia-southeast1`) and capture what came back + timing. Throwaway code. No app, no DB, no LiveKit Cloud.

## Requirements

- Functional: send mic/recorded audio to Gemini Live, receive audio + text response, log transcript-in / transcript-out / timestamps.
- Non-functional: runs on one laptop in Vietnam (real network path VN→SG); cheap; deletable in one folder.

## Architecture

Two candidate harnesses — **start with A**, escalate to B only if turn-cutoff is the deciding question:

- **A. Direct Gemini Live (recommended first):** small Python script using the Google GenAI live SDK → opens a live session to the native-audio model in `asia-southeast1` → streams audio in, plays/records audio out, logs Gemini's input-transcription + output-transcription + latency stamps. Fastest path to truth on understanding / code-switch / latency / safety.
- **B. Minimal LiveKit Agent (only if needed):** tiny `livekit-agents` Python worker + `livekit-plugins-google` realtime → lets us tune `min_endpointing_delay` (~1.2-1.5s) and observe whether the turn-detector fixes the #2117 cutoff for slow kids. Use ONLY to answer the cutoff question; not for the other metrics.

Decision rule: run A for understanding/latency/code-switch/safety. If A shows cutoff problems on slow speech, run B to check if LiveKit turn-detector tuning resolves them (that directly informs whether B's extra hop is justified vs pivoting to C).

## Related Code Files

- Create: `spike/gemini_live_direct_probe.py` (harness A — direct live session)
- Create: `spike/livekit_agent_probe.py` (harness B — only if escalated)
- Create: `spike/requirements.txt` (pinned: google-genai live SDK; optionally livekit-agents + livekit-plugins-google)
- Create: `spike/.env.example` (GOOGLE_CLOUD_PROJECT, region, model id — real `.env` git-ignored, never committed)
- Create: `spike/README.md` (how to run; "THROWAWAY — delete after Phase 0")
- Note: `spike/` is throwaway; not part of the eventual app tree.

## Implementation Steps

1. Confirm prerequisites: GCP project with Vertex AI + Gemini Live enabled in `asia-southeast1`, billing on, local auth (`gcloud auth application-default login`).
2. **Resolve model id (Open Question #1):** look up the current stable native-audio Gemini Live model from Vertex AI docs at spike time — do NOT hardcode a remembered/preview id (preview deprecated 2026-03). Put it in `.env`.
3. Write harness A: open live session → stream audio in → receive audio out → enable input+output transcription → log `{utterance_id, in_text, out_text, t_user_end, t_first_audio, t_complete}` to a JSONL file.
4. Apply spike system prompt: "bạn của trẻ 5 tuổi", song ngữ EN/VN, câu ngắn nói chậm, dừng cho bé phản hồi, chủ đề an toàn, từ chối nhẹ + chuyển hướng. Set Gemini safety = strict.
5. Smoke test with adult voice (you) in VN + EN + a mixed sentence; confirm logging + latency stamps work and audio round-trips.
6. Prep child-sample workflow (Open Question #3): record short real utterances locally; replay through harness OR talk live; **store audio locally only, delete after scoring; no retention**.
7. (Conditional) If escalation likely, scaffold harness B with `min_endpointing_delay` configurable via env.

## Success Criteria

- [ ] Harness A round-trips audio VN→SG and logs in/out text + latency stamps to JSONL.
- [ ] Model id resolved from current docs (not memory), recorded in `.env`.
- [ ] Spike system prompt + strict safety applied.
- [ ] Adult smoke test passes (VN, EN, mixed) with sane latency numbers.
- [ ] Child-sample capture workflow ready with local-only, delete-after-scoring handling.
- [ ] `spike/` clearly marked throwaway; no secrets committed.

## Risk Assessment

- **Vertex/region access not provisioned** → blocks everything; verify Step 1 before coding.
- **SDK / model-id churn** (preview deprecations) → resolve live from docs, pin in `.env`.
- **Accidentally building production scaffolding** → keep everything under `spike/`, resist adding app structure.
- **Child audio handling** → local-only, delete after scoring; smallest ethical footprint.
