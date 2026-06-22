"""End-of-session memory summarizer.

After a session, fold the prior memory + this session's transcript into a short,
child-safe summary the companion can recall next time. Uses a cheap TEXT model
(not the live audio model) for a single `generate_content` call.

Best-effort by contract: any failure returns the prior summary unchanged, so a
slow/failed summary never loses memory or breaks session teardown.
"""

from __future__ import annotations

import logging

from google import genai
from google.genai import types

import gemini_session_config as cfg

logger = logging.getLogger("memory_summarizer")

# Keep the stored memory small so it never bloats the system prompt.
_MAX_SUMMARY_CHARS = 800

_SUMMARY_INSTRUCTION = """\
Bạn đang giúp một người bạn ảo NHỚ về một em bé 5 tuổi giữa các buổi trò chuyện.
You maintain a memory note about a 5-year-old child for their imaginary friend.

Dựa trên ghi nhớ trước đó và đoạn hội thoại mới, hãy CẬP NHẬT ghi nhớ:
Using the prior memory and the new conversation, UPDATE the memory note:
- Viết 3-5 câu NGẮN, ấm áp, chỉ nêu sự thật. Write 3-5 short, warm, factual sentences.
- CHỈ dùng điều thực sự xuất hiện trong hội thoại. Use ONLY what actually appears.
- KHÔNG suy diễn, KHÔNG bịa. No speculation, no invention.
- Gộp lại thành một ghi nhớ duy nhất, không nối dài vô tận. Merge into ONE concise note.
- Chỉ nội dung phù hợp trẻ em. Child-appropriate content only.

Trả về DUY NHẤT đoạn ghi nhớ đã cập nhật, không thêm lời dẫn.
Return ONLY the updated memory note, no preamble.
"""


async def summarize(
    client: genai.Client, prior_summary: str, transcript_text: str
) -> str:
    """Return an updated memory summary, or the prior one on any failure."""
    prompt = (
        f"{_SUMMARY_INSTRUCTION}\n\n"
        f"--- Ghi nhớ trước đó / Prior memory ---\n{prior_summary or '(chưa có / none)'}\n\n"
        f"--- Hội thoại buổi này / This session ---\n{transcript_text}\n"
    )
    try:
        resp = await client.aio.models.generate_content(
            model=cfg.summary_model_id(),
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.2,
                # A short factual summary needs no reasoning; disabling thinking
                # stops the (2.5-flash) thinking budget from eating the output
                # tokens and truncating the note. Generous cap for Vietnamese
                # (more tokens per word than English).
                thinking_config=types.ThinkingConfig(thinking_budget=0),
                max_output_tokens=1024,
                safety_settings=[
                    types.SafetySetting(category=cat, threshold="BLOCK_LOW_AND_ABOVE")
                    for cat in cfg.SAFETY_CATEGORIES
                ],
            ),
        )
        text = (resp.text or "").strip()
        if not text:
            logger.warning("empty summary returned; keeping prior")
            return prior_summary
        # If the model still hit the token ceiling, the note is cut mid-sentence —
        # don't persist a truncated summary; keep the prior one.
        if _was_truncated(resp):
            logger.warning("summary truncated (max tokens); keeping prior")
            return prior_summary
        return text[:_MAX_SUMMARY_CHARS]
    except Exception as exc:  # noqa: BLE001 - best-effort; keep prior on any error
        logger.warning("summary failed (%s); keeping prior", exc)
        return prior_summary


def _was_truncated(resp) -> bool:
    """True if generation stopped because it hit the output-token ceiling."""
    try:
        return any(
            c.finish_reason == types.FinishReason.MAX_TOKENS
            for c in (resp.candidates or [])
        )
    except Exception:  # noqa: BLE001 - never let a check break the summary path
        return False
