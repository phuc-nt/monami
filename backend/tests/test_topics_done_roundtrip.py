"""Done-topic round-trip in the LAYERED model: the curriculum loader and the
session-end merge agree on the "<mode>:<id>" token, so a finished topic is
recorded into the `done_topics` array and the next session in that mode advances.
Also covers legacy `đã học:` text → array migration and the guest invariant.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import curriculum  # noqa: E402
import gemini_session  # noqa: E402


@pytest.fixture(autouse=True)
def _clear_cache():
    curriculum._cache.clear()
    yield
    curriculum._cache.clear()


def _mem(summary="", done_topics=None, facts=None):
    return {
        "summary": summary,
        "done_topics": list(done_topics or []),
        "facts": facts or {"pets": [], "likes": [], "dislikes": []},
    }


def test_done_token_format_matches_loader():
    # The token the merge records and the token the loader checks are identical.
    assert curriculum.done_note("english", "animals") == "đã học: english:animals"
    # The loader treats a topic in the done_topics array as done.
    assert curriculum._topic_done("", "english", "animals", ["english:animals"])


def test_roundtrip_advances_to_next_topic(tmp_path, monkeypatch):
    (tmp_path / "english.json").write_text(
        json.dumps(
            [
                {"id": "animals", "title_vi": "Con vật", "words": [],
                 "sentence_en": "", "sentence_vi": ""},
                {"id": "food", "title_vi": "Đồ ăn", "words": [],
                 "sentence_en": "", "sentence_vi": ""},
            ]
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(curriculum, "_DIR", tmp_path)
    curriculum._cache.clear()

    # First session: empty done_topics → first topic.
    t1 = curriculum.load_topic("english", "", done_topics=[])
    assert t1["id"] == "animals"

    # The session records the done-topic token into the array (what _merge_done
    # _topics produces given this session's marker).
    done_topics = gemini_session._merge_done_topics(_mem(), f"english:{t1['id']}")
    assert "english:animals" in done_topics

    # Next session in the SAME mode → loader skips the done topic → advances.
    t2 = curriculum.load_topic("english", "", done_topics=done_topics)
    assert t2["id"] == "food"


def test_merge_done_topics_unions_and_dedups():
    # Prior array + this session's marker, order-stable + de-duplicated.
    prior = _mem(done_topics=["english:animals"])
    out = gemini_session._merge_done_topics(prior, "english:food")
    assert out == ["english:animals", "english:food"]
    # Re-recording an already-done topic doesn't duplicate it.
    assert gemini_session._merge_done_topics(_mem(done_topics=out), "english:food") == out
    # Free chat (no marker) preserves the array unchanged.
    assert gemini_session._merge_done_topics(_mem(done_topics=out), "") == out


def test_legacy_text_markers_migrate_into_array():
    # A legacy doc has done-state ONLY in the summary text (đã học: lines). The
    # merge parses those into the array (the migration), keeping done-state.
    legacy_summary = "Bé thích con vật.\nđã học: english:animals\nđã học: science:why-rain"
    out = gemini_session._merge_done_topics(_mem(summary=legacy_summary), "english:food")
    assert "english:animals" in out
    assert "science:why-rain" in out
    assert "english:food" in out


def test_legacy_text_path_still_advances_before_migration():
    # Transitional: a child whose done-state is ONLY in legacy text (no array yet)
    # must NOT re-learn a finished topic on the first post-deploy session.
    legacy = "Bé học rồi.\nđã học: english:animals"
    assert curriculum._topic_done(legacy, "english", "animals", done_topics=[])
    assert not curriculum._topic_done(legacy, "english", "food", done_topics=[])


def test_prefix_topic_id_not_a_false_positive():
    # A longer id ("foods") recorded done must NOT mark a shorter id ("food") done,
    # via BOTH the array path and the legacy text path.
    assert curriculum._topic_done("", "english", "foods", ["english:foods"])
    assert not curriculum._topic_done("", "english", "food", ["english:foods"])
    legacy = f"Bé học rồi.\n{curriculum.done_note('english', 'foods')}"
    assert curriculum._topic_done(legacy, "english", "foods", done_topics=[])
    assert not curriculum._topic_done(legacy, "english", "food", done_topics=[])


def test_free_chat_yields_no_topic():
    # No mode → load_topic is None regardless of done state.
    assert curriculum.load_topic(None, "", done_topics=["english:animals"]) is None
