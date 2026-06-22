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


def build_system_prompt(profile: ChildProfile, memory_text: str = "") -> str:
    """Base persona + the selected child's profile + (optional) remembered memory.

    memory_text is a short AI-generated summary of past sessions (see
    memory_summarizer / profile_store); omitted when empty (first session).
    """
    parts = [_BASE_SYSTEM_PROMPT, "", profile.to_prompt_text()]
    if memory_text.strip():
        parts += [
            "",
            "Điều bạn còn nhớ về bé / What you remember about the child:",
            memory_text.strip(),
            "Hãy dùng những điều này một cách tự nhiên, ấm áp khi hợp lý. "
            "Use these naturally and warmly when it fits.",
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
    only one that serves native audio (us-central1)."""
    project = os.environ.get("GOOGLE_CLOUD_PROJECT")
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
    if not project:
        raise RuntimeError(
            "GOOGLE_CLOUD_PROJECT not set. Copy backend/.env.example to backend/.env."
        )
    return project, location


def build_live_connect_config(
    profile: ChildProfile, memory_text: str = ""
) -> types.LiveConnectConfig:
    """LiveConnectConfig: audio-only out, both transcriptions, strict safety,
    bilingual system prompt for the selected child + their remembered memory.
    Mirrors the Phase 0 spike (config) with per-child personalization added."""
    return types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=types.Content(
            parts=[types.Part(text=build_system_prompt(profile, memory_text))]
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
