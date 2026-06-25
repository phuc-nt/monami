"""Verified Gemini Live config for the voice-companion backend.

Lifted and tidied from the Phase 0 spike (spike/gemini_live_direct_probe.py).
Every constant here was validated live with real Vietnamese 5-year-old speech in
Phase 0 — do NOT change them without re-running that validation:

  - Region us-central1, model gemini-live-2.5-flash-native-audio (only region
    that serves native audio).
  - input_audio_transcription.language_hints = ["vi-VN", "en-US"] — auto-detect
    mis-hears VN child speech; hints fix the transcript and still allow EN/VN
    code-switching.
  - End-of-turn = trailing silence + server VAD (the native-audio model IGNORES
    audio_stream_end and hangs). See END_SILENCE_MS.
  - response_modalities = ["AUDIO"] only (TEXT is unsupported → error 1007).
  - Strict safety: BLOCK_LOW_AND_ABOVE on the four configurable harm categories.

This module owns config only; the relay logic lives in gemini_session.py.
"""

from __future__ import annotations

import os

from google.genai import types

import learning_modes
from child_profile import ChildProfile

# --- Audio format (Gemini Live: 16 kHz mono PCM in, 24 kHz mono PCM out). ---
INPUT_SAMPLE_RATE = 16_000
OUTPUT_SAMPLE_RATE = 24_000
CHANNELS = 1
SAMPLE_WIDTH_BYTES = 2  # 16-bit PCM

# Trailing silence appended after a child's utterance so the native-audio model's
# server-side VAD detects end-of-turn. ~800 ms verified in Phase 0; this is the
# tuning knob for the slow-speech cutoff gate (Phase 4) — raise if kids get cut off.
END_SILENCE_MS = 800

# Language hints for INPUT transcription (see module docstring). Hints guide,
# they don't hard-lock like the deprecated language_codes, so code-switching works.
TRANSCRIPTION_LANGUAGE_HINTS = ["vi-VN", "en-US"]

# Strict safety: block at the lowest threshold across configurable categories.
# Child-safety harms (e.g. CSAM) are always blocked by the platform regardless.
SAFETY_CATEGORIES = [
    "HARM_CATEGORY_HARASSMENT",
    "HARM_CATEGORY_HATE_SPEECH",
    "HARM_CATEGORY_SEXUALLY_EXPLICIT",
    "HARM_CATEGORY_DANGEROUS_CONTENT",
]

# Bilingual EN/VN "friend for a 5-year-old" persona. The child profile is stuffed
# in at the end so the companion greets by name and references an interest.
_BASE_SYSTEM_PROMPT = """\
Bạn là một người bạn ảo thân thiện, ấm áp, kiên nhẫn của một em bé 5 tuổi.
You are a warm, friendly, patient imaginary friend for a 5-year-old child.

Cách nói chuyện / How you talk:
- Nói câu NGẮN, từ ĐƠN GIẢN. Use SHORT sentences and SIMPLE words.
- Nói CHẬM RÃI và DỪNG lại để bé kịp trả lời. Speak slowly; pause so the child can respond.
- Mặc định dùng ngôn ngữ mà bé đang dùng. Default to whatever language the child uses.
- Chêm/chuyển sang tiếng Anh một cách TỰ NHIÊN, không ép. Mix in English naturally; never force it.
- Giọng vui vẻ, khích lệ, KHÔNG phán xét. Be cheerful and encouraging; never judgmental.

An toàn / Safety:
- Chỉ nói nội dung phù hợp với trẻ 5 tuổi. Only ever say things appropriate for a 5-year-old.
- Nếu gặp chủ đề không phù hợp hay đáng sợ, từ chối NHẸ NHÀNG và chuyển hướng sang
  điều vui vẻ, an toàn. If a topic is unsafe or scary, gently decline and redirect to
  something cheerful and safe.
"""


def _render_facts(facts: dict | None) -> str:
    """A short bilingual durable-facts block, or "" when there's nothing to render.

    Returns "" unless `any(facts.values())` is truthy — a default empty-keys dict
    `{"pets":[],"likes":[],"dislikes":[]}` is falsy here, so a child with no facts
    yet produces a BYTE-IDENTICAL prompt to before this feature existed.
    """
    if not facts or not any(facts.values()):
        return ""
    labels = (
        ("pets", "Thú cưng / Pets"),
        ("likes", "Bé thích / Likes"),
        ("dislikes", "Bé không thích / Dislikes"),
    )
    lines = []
    for key, label in labels:
        vals = facts.get(key) or []
        if vals:
            lines.append(f"- {label}: {', '.join(str(v) for v in vals)}")
    return "\n".join(lines)


def build_system_prompt(
    profile: ChildProfile,
    memory_text: str = "",
    mode: str | None = None,
    lesson: str = "",
    facts: dict | None = None,
) -> str:
    """Base persona + the selected child's profile + (optional) remembered memory
    (durable `facts` + soft `memory_text` summary), and — when a learning `mode`
    is active — that mode's leading script + the chosen `lesson` content.

    `facts` are durable, code-merged truths about the child (pets/likes/dislikes);
    `memory_text` is the soft AI summary of past sessions. Both are omitted when
    empty (a child with neither yields a byte-identical free-chat prompt).

    `mode`/`lesson` are optional: with no mode (free chat) the prompt is exactly
    the persona + profile + memory, unchanged — so existing behavior is preserved.
    """
    parts = [_BASE_SYSTEM_PROMPT, "", profile.to_prompt_text()]
    facts_block = _render_facts(facts)
    if facts_block:
        parts += [
            "",
            "Sự thật bạn luôn nhớ về bé / Durable facts about the child:",
            facts_block,
        ]
    if memory_text.strip():
        parts += [
            "",
            "Điều bạn còn nhớ về bé / What you remember about the child:",
            memory_text.strip(),
            "Hãy dùng những điều này một cách tự nhiên, ấm áp khi hợp lý. "
            "Use these naturally and warmly when it fits.",
        ]
    # Learning mode (optional): append the pedagogy framing, an age-tuned
    # difficulty line, + today's lesson. All of this lives INSIDE this branch so
    # free chat (no/unknown mode → empty script) is byte-identical to before.
    script = learning_modes.leading_script(mode)
    if script:
        parts += ["", script]
        parts += ["", learning_modes.age_band_line(profile.age)]
        if lesson.strip():
            parts += [
                "",
                "Nội dung bài hôm nay / Today's lesson:",
                lesson.strip(),
            ]
    return "\n".join(parts) + "\n"


def input_audio_mime_type() -> str:
    """MIME type for raw PCM frames sent to Gemini (16 kHz mono 16-bit)."""
    return f"audio/pcm;rate={INPUT_SAMPLE_RATE}"


def model_id() -> str:
    """Native-audio model id from env (set in .env; see .env.example)."""
    model = os.environ.get("GEMINI_LIVE_MODEL")
    if not model:
        raise RuntimeError(
            "GEMINI_LIVE_MODEL not set. Copy backend/.env.example to backend/.env."
        )
    return model


def summary_model_id() -> str:
    """Cheap TEXT model for end-of-session memory summaries (not the live model).
    Override with MEMORY_SUMMARY_MODEL. Default is a current Vertex flash text
    model (2.0-flash was retired 2026-06; do not revert to it)."""
    return os.environ.get("MEMORY_SUMMARY_MODEL", "gemini-2.5-flash")


def project_and_location() -> tuple[str, str]:
    """GCP project + region for the Vertex AI client. Region defaults to the
    only one that serves native audio (us-central1). The project comes from
    GOOGLE_CLOUD_PROJECT if set, else from ADC (the metadata server on Cloud Run /
    the gcloud default locally) — so the env var is optional in the cloud."""
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
    project = (
        os.environ.get("GOOGLE_CLOUD_PROJECT")
        or os.environ.get("GOOGLE_CLOUD_QUOTA_PROJECT")
        or _project_from_adc()
    )
    if not project:
        raise RuntimeError(
            "No GCP project found. Set GOOGLE_CLOUD_PROJECT (env/.env) or run "
            "`gcloud auth application-default login` locally."
        )
    return project, location


def _project_from_adc() -> str | None:
    """Best-effort project id from Application Default Credentials."""
    try:
        import google.auth

        _, project = google.auth.default()
        return project
    except Exception:  # noqa: BLE001 - fall through to the explicit error
        return None


def build_live_connect_config(
    profile: ChildProfile,
    memory_text: str = "",
    mode: str | None = None,
    lesson: str = "",
    facts: dict | None = None,
) -> types.LiveConnectConfig:
    """LiveConnectConfig: audio-only out, both transcriptions, strict safety,
    bilingual system prompt for the selected child + their remembered memory
    (durable `facts` + soft `memory_text`), and (optionally) a learning mode's
    script + lesson. With no mode + no facts it is identical to the free-chat
    config. Audio/safety/hints are unchanged regardless of mode."""
    return types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=types.Content(
            parts=[
                types.Part(
                    text=build_system_prompt(
                        profile, memory_text, mode, lesson, facts=facts
                    )
                )
            ]
        ),
        # Transcribe BOTH sides: input for dev visibility + language hinting,
        # output so the client can show what the companion said.
        input_audio_transcription=types.AudioTranscriptionConfig(
            language_hints=types.LanguageHints(
                language_codes=TRANSCRIPTION_LANGUAGE_HINTS
            )
        ),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        safety_settings=[
            types.SafetySetting(category=cat, threshold="BLOCK_LOW_AND_ABOVE")
            for cat in SAFETY_CATEGORIES
        ],
    )
