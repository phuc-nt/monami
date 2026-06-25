"""End-of-session memory summarizer (layered: durable facts + soft summary).

After a session, fold the prior memory + this session's transcript into BOTH:
  - `facts`: newly-observed durable facts about the CHILD (pets/likes/dislikes),
    which code merges as a union and never overwrites; and
  - `summary`: a short, child-safe soft recap the companion can recall next time.

One `generate_content` call using SDK **structured output**
(`response_mime_type="application/json"` + `response_schema`) so the result parses
reliably even if the model would otherwise wrap JSON in a ```fence``` or add a
preamble — bare `json.loads` on free-form model text silently no-ops facts.

Best-effort by contract: any failure returns the PRIOR facts + prior summary
unchanged, so a slow/failed summary never loses memory or breaks teardown.
"""

from __future__ import annotations

import logging

from google import genai
from google.genai import types

import gemini_session_config as cfg

logger = logging.getLogger("memory_summarizer")

# Keep the stored memory small so it never bloats the system prompt.
_MAX_SUMMARY_CHARS = 800

# Durable-fact keys the model may report. MUST mirror child_store._FACTS_KEYS.
_FACTS_KEYS = ("pets", "likes", "dislikes")

# Structured-output schema: a flat object with the soft summary + the three fact
# lists. The model is forced to emit exactly this shape (no fences, no preamble).
_RESPONSE_SCHEMA = types.Schema(
    type=types.Type.OBJECT,
    properties={
        "summary": types.Schema(type=types.Type.STRING),
        "pets": types.Schema(
            type=types.Type.ARRAY, items=types.Schema(type=types.Type.STRING)
        ),
        "likes": types.Schema(
            type=types.Type.ARRAY, items=types.Schema(type=types.Type.STRING)
        ),
        "dislikes": types.Schema(
            type=types.Type.ARRAY, items=types.Schema(type=types.Type.STRING)
        ),
    },
    required=["summary", "pets", "likes", "dislikes"],
)

_SUMMARY_INSTRUCTION = """\
Bạn đang giúp một người bạn ảo NHỚ về một em bé 5 tuổi giữa các buổi trò chuyện.
You maintain a memory note about a 5-year-old child for their imaginary friend.

Dựa trên ghi nhớ trước đó và đoạn hội thoại mới, hãy trả về:
Using the prior memory and the new conversation, return:
- summary: 3-5 câu NGẮN, ấm áp, chỉ nêu sự thật. 3-5 short, warm, factual sentences.
- pets: tên/loại thú cưng của bé. The child's pets (names/kinds), if any.
- likes: những thứ bé THÍCH. Things the child LIKES.
- dislikes: những thứ bé KHÔNG thích / sợ. Things the child dislikes or fears.

Quy tắc / Rules:
- CHỈ dùng điều thực sự xuất hiện trong hội thoại HOẶC ghi nhớ trước. Use ONLY what
  actually appears in the conversation OR the prior memory. KHÔNG bịa. No invention.
- Mỗi mục facts là cụm NGẮN (vài từ). Each fact item is a SHORT phrase (a few words).
- Nếu không có gì cho một mục, trả về danh sách RỖNG. If nothing for a key, return [].
- summary gộp thành MỘT ghi nhớ ngắn. Merge summary into ONE concise note.
- Chỉ nội dung phù hợp trẻ em. Child-appropriate content only.
"""


async def summarize(
    client: genai.Client, prior: dict, transcript_text: str
) -> dict:
    """Return updated {facts:{pets,likes,dislikes}, summary} for this session.

    `prior` is the child's current layered memory struct ({facts, summary, ...});
    on ANY failure this returns {facts: prior facts, summary: prior summary} so a
    failed call never resets durable facts to empty.
    """
    prior_facts = prior.get("facts") or {k: [] for k in _FACTS_KEYS}
    prior_summary = str(prior.get("summary", ""))
    fallback = {"facts": prior_facts, "summary": prior_summary}

    prior_block = _render_prior(prior_facts, prior_summary)
    prompt = (
        f"{_SUMMARY_INSTRUCTION}\n\n"
        f"--- Ghi nhớ trước đó / Prior memory ---\n{prior_block}\n\n"
        f"--- Hội thoại buổi này / This session ---\n{transcript_text}\n"
    )
    try:
        resp = await client.aio.models.generate_content(
            model=cfg.summary_model_id(),
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.2,
                # A short factual summary needs no reasoning; disabling thinking
                # stops the (2.5-flash) thinking budget from eating output tokens.
                thinking_config=types.ThinkingConfig(thinking_budget=0),
                max_output_tokens=1024,
                response_mime_type="application/json",
                response_schema=_RESPONSE_SCHEMA,
                safety_settings=[
                    types.SafetySetting(category=cat, threshold="BLOCK_LOW_AND_ABOVE")
                    for cat in cfg.SAFETY_CATEGORIES
                ],
            ),
        )
        if _was_truncated(resp):
            logger.warning("summary truncated (max tokens); keeping prior")
            return fallback
        data = _parse(resp)
        if data is None:
            logger.warning("summary unparseable; keeping prior")
            return fallback
        summary = str(data.get("summary", "")).strip()[:_MAX_SUMMARY_CHARS]
        if not summary:
            summary = prior_summary  # never blank out a good recap
        facts = {k: _clean_list(data.get(k)) for k in _FACTS_KEYS}
        return {"facts": facts, "summary": summary}
    except Exception as exc:  # noqa: BLE001 - best-effort; keep prior on any error
        logger.warning("summary failed (%s); keeping prior", exc)
        return fallback


def _render_prior(facts: dict, summary: str) -> str:
    """Feed the prior memory back to the model as readable context."""
    lines = [summary or "(chưa có / none)"]
    for k in _FACTS_KEYS:
        vals = facts.get(k) or []
        if vals:
            lines.append(f"{k}: {', '.join(str(v) for v in vals)}")
    return "\n".join(lines)


def _parse(resp) -> dict | None:
    """The structured-output object, parsed defensively.

    Prefers the SDK's already-parsed `.parsed`; falls back to json.loads on
    `.text` (which, under response_mime_type=json, is raw JSON — no fence). None
    if neither yields a dict.
    """
    parsed = getattr(resp, "parsed", None)
    if isinstance(parsed, dict):
        return parsed
    text = (getattr(resp, "text", None) or "").strip()
    if not text:
        return None
    text = _strip_fence(text)
    import json

    try:
        obj = json.loads(text)
        return obj if isinstance(obj, dict) else None
    except (json.JSONDecodeError, ValueError):
        return None


def _strip_fence(text: str) -> str:
    """Strip a leading/trailing markdown code fence if present.

    response_mime_type=application/json should prevent fences, but a model can
    still wrap JSON in ```json ... ``` — defense-in-depth so facts never silently
    no-op (red-team C2). Returns the inner content (or the text unchanged).
    """
    if not text.startswith("```"):
        return text
    inner = text[3:]
    # Drop an optional language tag on the first line (e.g. "json").
    newline = inner.find("\n")
    if newline != -1:
        inner = inner[newline + 1:]
    if inner.rstrip().endswith("```"):
        inner = inner.rstrip()[:-3]
    return inner.strip()


def _clean_list(value) -> list[str]:
    """Normalize a model-reported fact list to clean short strings (drop blanks)."""
    if not isinstance(value, list):
        return []
    out = []
    for item in value:
        s = str(item).strip()
        if s:
            out.append(s)
    return out


def _was_truncated(resp) -> bool:
    """True if generation stopped because it hit the output-token ceiling."""
    try:
        return any(
            c.finish_reason == types.FinishReason.MAX_TOKENS
            for c in (resp.candidates or [])
        )
    except Exception:  # noqa: BLE001 - never let a check break the summary path
        return False
