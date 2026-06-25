"""Curriculum loader: turn a learning mode into a compact lesson for the prompt.

Each learning mode (`english`/`science`) has a small JSON file under
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

import child_store
import learning_modes

logger = logging.getLogger("curriculum")

_DIR = Path(__file__).parent / "curriculum"

# Cap the rendered lesson so it can't bloat the system prompt (chars).
_MAX_LESSON_CHARS = 800

# Optional doc fields tolerated on a Firestore topic (unknown → defaults):
#   order:int   sort key (missing → 0, then by id)
#   enabled:bool  False → topic skipped entirely
#   age_band:str  ignored by the loader for now (forward-compat metadata)

# Parsed-topic cache, keyed by mode. Stores ONLY successful Firestore reads — a
# JSON fallback is served but NOT cached, so the next request retries Firestore
# (a cold-start Firestore blip must not pin the JSON fallback for the instance's
# life). Topics are tiny + change rarely, so a process-lifetime cache is fine.
_cache: dict[str, list[dict]] = {}


def _load_topics(mode: str) -> list[dict]:
    """Topics for a mode, from Firestore (cached on success) else bundled JSON.

    Firestore is the source of truth so lessons can be added without a rebuild;
    the repo JSON is the resilient fallback. ONLY a successful Firestore read is
    cached — a fallback result is returned uncached so a transient Firestore
    failure self-heals on the next request.
    """
    if mode in _cache:
        return _cache[mode]
    topics = _load_firestore(mode)
    if topics is not None:
        _cache[mode] = topics  # cache successful reads only
        return topics
    # Firestore unavailable/empty → bundled JSON, NOT cached (retry next time).
    return _load_json_fallback(mode)


def _load_firestore(mode: str) -> list[dict] | None:
    """Read enabled topics from `{PREFIX}curriculum/{mode}/topics`, sorted by
    `order` then id. Returns the list on success (possibly empty-but-present is
    treated as "no content" → None so the JSON fallback fills in), or None on any
    error/empty so the caller falls back to bundled JSON without caching.

    Skipped entirely in JSON/local-dev mode (no GCP) — there the bundled JSON IS
    the source, so we never pay a Firestore connection attempt/timeout.
    """
    if child_store._backend() != "firestore":
        return None
    try:
        col = (
            child_store._client()
            .collection(child_store.prefixed("curriculum"))
            .document(mode)
            .collection("topics")
        )
        docs = list(col.stream())
    except Exception as exc:  # noqa: BLE001 - storage must never break a session
        logger.warning("curriculum firestore read failed for %s: %s", mode, exc)
        return None
    topics: list[dict] = []
    for snap in docs:
        data = snap.to_dict() or {}
        if data.get("enabled") is False:
            continue
        data.setdefault("id", snap.id)
        if not data.get("id"):
            continue
        topics.append(data)
    if not topics:
        # Empty (unseeded / all disabled) → fall back to JSON; don't cache "[]".
        return None
    topics.sort(key=lambda t: (_order_of(t), str(t.get("id"))))
    return topics


def _order_of(topic: dict) -> int:
    """Sort key from the optional `order` field (missing/non-int → 0)."""
    value = topic.get("order")
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def _load_json_fallback(mode: str) -> list[dict]:
    """Bundled-JSON topic list for a mode ([] on any problem). NOT cached."""
    path = _DIR / f"{mode}.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        logger.warning("curriculum file missing: %s", path.name)
        return []
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("curriculum %s unreadable: %s", path.name, exc)
        return []
    if not isinstance(data, list):
        logger.warning("curriculum %s: expected a list", path.name)
        return []
    return [t for t in data if isinstance(t, dict) and t.get("id")]


# Marker the memory summary uses to record a finished topic. The summarizer
# writes exactly `done_note(...)`; the matcher anchors on the same string so a
# topic id that merely appears as a word in the free-form summary (e.g.
# "animals") can't cause a false "done". One producer, one consumer, one format.
DONE_MARKER = "đã học:"


def done_note(mode: str, topic_id: str) -> str:
    """The exact note recorded in memory when a topic is finished, e.g.
    "đã học: english:animals". The summarizer appends this; `_topic_done` looks
    for it — both go through here so they can never drift."""
    return f"{DONE_MARKER} {mode}:{topic_id}"


def _topic_done(
    memory_text: str,
    mode: str,
    topic_id: str,
    done_topics: list[str] | None = None,
) -> bool:
    """Has the child already done this topic?

    True if the topic is in the `done_topics` ARRAY (the source of truth in the
    layered model) OR — permanently, for back-compat — if a legacy `đã học:` line
    in the free-form `memory_text` records it. Keeping the legacy text path means a
    child whose done-state still lives only in old summary text never re-learns a
    finished topic in the first post-deploy session.

    Anchoring on the structured marker AND requiring end-of-line means one topic id
    can't be a substring of another — "food" won't match a line ending "...:foods".
    """
    token = f"{mode}:{topic_id}"
    if done_topics and token in done_topics:
        return True
    if not memory_text:
        return False
    note = done_note(mode, topic_id)
    return any(line.rstrip().endswith(note) for line in memory_text.splitlines())


def load_topic(
    mode: str | None,
    memory_text: str = "",
    done_topics: list[str] | None = None,
) -> dict | None:
    """Pick today's topic for a learning mode, or None (free chat / no content).

    First topic the child hasn't done (per `done_topics` array OR legacy text);
    else the first topic (round-robin would need persisted state we don't have —
    first-not-done is the simplest useful rule). None when the mode isn't a
    learning mode or the file is missing/empty.
    """
    resolved = learning_modes.parse_mode(mode)
    if resolved is None:
        return None
    topics = _load_topics(resolved)
    if not topics:
        return None
    for t in topics:
        if not _topic_done(memory_text, resolved, str(t["id"]), done_topics):
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
    elif resolved == learning_modes.SCIENCE:
        out = _render_science(topic)
    else:  # pragma: no cover - parse_mode guarantees one of the above
        out = ""
    return out[:_MAX_LESSON_CHARS].rstrip()


# Curriculum schema (v2) — fields a topic may carry:
#   english topic: id, title_vi, words[{en,vi}], sentence_en, sentence_vi,
#                  elicit_vi (optional) — a recall prompt the model uses to make
#                  the child SAY the words back (active recall).
#   science topic: id, question_vi, answer_vi, follow_up_vi,
#                  predict_vi (optional) — the "guess why first" prompt, rendered
#                  BEFORE the suggested answer so the model elicits a guess first.
# All the v2 fields are optional + read via .get(); a topic without them still
# renders (backward compatible). Adding a topic is data, not code.
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
    if t.get("elicit_vi"):
        lines.append(f"Gợi bé nói lại / Recall prompt: {t['elicit_vi']}")
    return "\n".join(lines)


def _render_science(t: dict) -> str:
    lines = [f"Câu hỏi / Question: {t.get('question_vi','')}"]
    # Predict comes BEFORE the answer: the model should ask the child to guess
    # "why" first, then explain.
    if t.get("predict_vi"):
        lines.append(f"Hỏi bé đoán trước / Ask to predict: {t['predict_vi']}")
    if t.get("answer_vi"):
        lines.append(f"Trả lời gợi ý / Suggested answer: {t['answer_vi']}")
    if t.get("follow_up_vi"):
        lines.append(f"Hỏi thêm / Follow-up: {t['follow_up_vi']}")
    return "\n".join(lines)
