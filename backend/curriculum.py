"""Curriculum loader: turn a learning mode into a compact lesson for the prompt.

Each learning mode (`english`/`stories`/`science`) has a small JSON file under
`backend/curriculum/` listing topics. For a session we pick ONE topic — the first
the child hasn't done yet (read tolerantly from the per-child memory text; a later
phase writes the "done" notes, so before that we simply fall back to the first
topic) — and render it as a short bilingual block that's appended to the system
prompt. Only the chosen topic goes in the prompt, never the whole file, so the
prompt stays small.

Defensive: a missing or malformed file logs a warning and yields no lesson; the
mode then runs on its leading script alone (no crash).
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

import learning_modes

logger = logging.getLogger("curriculum")

_DIR = Path(__file__).parent / "curriculum"

# Cap the rendered lesson so it can't bloat the system prompt (chars).
_MAX_LESSON_CHARS = 800

# Parsed-file cache, keyed by mode. Files are tiny + static at runtime.
_cache: dict[str, list[dict]] = {}


def _load_file(mode: str) -> list[dict]:
    """Return the topic list for a mode ([] on any problem). Cached."""
    if mode in _cache:
        return _cache[mode]
    path = _DIR / f"{mode}.json"
    topics: list[dict] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            topics = [t for t in data if isinstance(t, dict) and t.get("id")]
        else:
            logger.warning("curriculum %s: expected a list", path.name)
    except FileNotFoundError:
        logger.warning("curriculum file missing: %s", path.name)
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("curriculum %s unreadable: %s", path.name, exc)
    _cache[mode] = topics
    return topics


# Marker the memory summary uses to record a finished topic. Phase 4's summarizer
# MUST write exactly this prefix; the matcher below anchors on it so a topic id
# that merely appears as a word in the free-form summary (e.g. "animals") can't
# cause a false "done".
DONE_MARKER = "đã học:"


def _topic_done(memory_text: str, mode: str, topic_id: str) -> bool:
    """Has the child already done this topic? (anchored on DONE_MARKER).

    Reads tolerantly from the free-form memory summary. Before phase 4 writes any
    done-note this returns False (→ first topic). Anchoring on the structured
    "đã học: <mode>:<id>" marker avoids false positives from ordinary words in the
    summary.
    """
    if not memory_text:
        return False
    return f"{DONE_MARKER} {mode}:{topic_id}" in memory_text


def load_topic(mode: str | None, memory_text: str = "") -> dict | None:
    """Pick today's topic for a learning mode, or None (free chat / no content).

    First topic the child hasn't done; else the first topic (round-robin would
    need persisted state we don't have — first-not-done is the simplest useful
    rule). None when the mode isn't a learning mode or the file is missing/empty.
    """
    resolved = learning_modes.parse_mode(mode)
    if resolved is None:
        return None
    topics = _load_file(resolved)
    if not topics:
        return None
    for t in topics:
        if not _topic_done(memory_text, resolved, str(t["id"])):
            return t
    # All done → cycle back to the first (keeps the activity going).
    return topics[0]


def render_lesson(mode: str | None, topic: dict | None) -> str:
    """Compact bilingual lesson block for the prompt (one topic only).

    Returns "" when there's no topic. Output is capped to _MAX_LESSON_CHARS.
    """
    resolved = learning_modes.parse_mode(mode)
    if resolved is None or not topic:
        return ""
    if resolved == learning_modes.ENGLISH:
        out = _render_english(topic)
    elif resolved == learning_modes.STORIES:
        out = _render_story(topic)
    elif resolved == learning_modes.SCIENCE:
        out = _render_science(topic)
    else:  # pragma: no cover - parse_mode guarantees one of the above
        out = ""
    return out[:_MAX_LESSON_CHARS].rstrip()


def _render_english(t: dict) -> str:
    words = "; ".join(
        f"{w.get('en','')} = {w.get('vi','')}" for w in t.get("words", [])
    )
    lines = [f"Chủ đề / Topic: {t.get('title_vi','')}"]
    if words:
        lines.append(f"Từ vựng / Words: {words}")
    if t.get("sentence_en") or t.get("sentence_vi"):
        lines.append(
            f"Câu mẫu / Sentence: {t.get('sentence_en','')} "
            f"({t.get('sentence_vi','')})"
        )
    return "\n".join(lines)


def _render_story(t: dict) -> str:
    chars = ", ".join(t.get("characters", []))
    lines = [f"Truyện / Story: {t.get('title_vi','')}"]
    if t.get("summary"):
        lines.append(f"Tóm tắt / Summary: {t['summary']}")
    if chars:
        lines.append(f"Nhân vật / Characters: {chars}")
    if t.get("moral_vi"):
        lines.append(f"Ý nghĩa / Moral: {t['moral_vi']}")
    return "\n".join(lines)


def _render_science(t: dict) -> str:
    lines = [f"Câu hỏi / Question: {t.get('question_vi','')}"]
    if t.get("answer_vi"):
        lines.append(f"Trả lời gợi ý / Suggested answer: {t['answer_vi']}")
    if t.get("follow_up_vi"):
        lines.append(f"Hỏi thêm / Follow-up: {t['follow_up_vi']}")
    return "\n".join(lines)
