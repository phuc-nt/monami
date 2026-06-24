"""Curriculum loader tests: schema validity, topic selection, defensive loading,
compact rendering, and that adding a topic is data (JSON), not code.
"""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import curriculum  # noqa: E402
import learning_modes  # noqa: E402

_CUR_DIR = Path(__file__).resolve().parent.parent / "curriculum"


@pytest.fixture(autouse=True)
def _clear_cache():
    # The loader caches parsed files; reset between tests so monkeypatched dirs
    # take effect.
    curriculum._cache.clear()
    yield
    curriculum._cache.clear()


def test_each_file_parses_and_matches_schema():
    eng = json.loads((_CUR_DIR / "english.json").read_text(encoding="utf-8"))
    assert eng and all(
        {"id", "title_vi", "words", "sentence_en", "sentence_vi"} <= t.keys()
        for t in eng
    )
    for t in eng:
        assert all({"en", "vi"} <= w.keys() for w in t["words"])

    sto = json.loads((_CUR_DIR / "stories.json").read_text(encoding="utf-8"))
    assert sto and all(
        {"id", "title_vi", "summary", "characters", "moral_vi"} <= t.keys()
        for t in sto
    )

    sci = json.loads((_CUR_DIR / "science.json").read_text(encoding="utf-8"))
    assert sci and all(
        {"id", "question_vi", "answer_vi", "follow_up_vi"} <= t.keys() for t in sci
    )


def test_load_topic_returns_a_topic_for_each_mode():
    for mode in learning_modes.VALID_MODES:
        t = curriculum.load_topic(mode, "")
        assert t is not None and t.get("id"), f"{mode} returned no topic"


def test_load_topic_none_for_free_chat_and_unknown():
    assert curriculum.load_topic(None, "") is None
    assert curriculum.load_topic("", "") is None
    assert curriculum.load_topic("math", "") is None  # deferred subject


def test_load_topic_skips_done_topics(tmp_path, monkeypatch):
    # Two topics; memory says the first is done → loader picks the second.
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
    t = curriculum.load_topic("english", "đã học: english:animals")
    assert t["id"] == "food"


def test_done_match_anchored_no_false_positive(tmp_path, monkeypatch):
    # A memory that merely MENTIONS the topic word ("animals") — without the
    # structured done-marker — must NOT skip it. Only the anchored marker counts.
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
    # Free-form memory mentions "animals" but has no done-marker → still topic 1.
    t = curriculum.load_topic("english", "Vy thích animals và vẽ tranh.")
    assert t["id"] == "animals"
    # With the anchored marker → skips to topic 2.
    t2 = curriculum.load_topic("english", f"{curriculum.DONE_MARKER} english:animals")
    assert t2["id"] == "food"


def test_missing_file_yields_none_no_crash(tmp_path, monkeypatch):
    monkeypatch.setattr(curriculum, "_DIR", tmp_path)  # empty dir
    curriculum._cache.clear()
    assert curriculum.load_topic("english", "") is None
    # render_lesson with no topic is "" (mode still runs on its leading script).
    assert curriculum.render_lesson("english", None) == ""


def test_broken_json_yields_none_no_crash(tmp_path, monkeypatch):
    (tmp_path / "stories.json").write_text("{ not json", encoding="utf-8")
    monkeypatch.setattr(curriculum, "_DIR", tmp_path)
    curriculum._cache.clear()
    assert curriculum.load_topic("stories", "") is None


def test_render_lesson_is_compact_and_bilingual():
    t = curriculum.load_topic("english", "")
    lesson = curriculum.render_lesson("english", t)
    assert lesson and len(lesson) <= curriculum._MAX_LESSON_CHARS
    # Contains both languages markers (the bilingual "/").
    assert "/" in lesson and ("=" in lesson or "Topic" in lesson)
    # Only ONE topic rendered: the other topic's title must not appear.
    other = [x for x in curriculum._load_file("english") if x["id"] != t["id"]]
    if other:
        assert other[0]["title_vi"] not in lesson


def test_adding_a_topic_is_just_json(tmp_path, monkeypatch):
    # Drop in an extra topic via a fixture file — no code change — and the loader
    # serves it. Proves content is data.
    (tmp_path / "science.json").write_text(
        json.dumps(
            [{"id": "why-rain", "question_vi": "Vì sao trời mưa?",
              "answer_vi": "Mây nặng nước thì rơi xuống thành mưa.",
              "follow_up_vi": "Con thích chơi gì khi trời mưa?"}]
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(curriculum, "_DIR", tmp_path)
    curriculum._cache.clear()
    t = curriculum.load_topic("science", "")
    assert t["id"] == "why-rain"
    assert "Vì sao trời mưa" in curriculum.render_lesson("science", t)


def test_free_chat_lesson_is_empty():
    # The backward-compat anchor: free chat → no topic → no lesson text.
    assert curriculum.render_lesson(None, None) == ""
    assert curriculum.load_topic(None, "anything") is None
