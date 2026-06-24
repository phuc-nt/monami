"""Phase-4 round-trip: the summarizer's done-note and the curriculum loader's
done-detection use the SAME format (curriculum.done_note), so a finished topic is
recorded and the next session in that mode advances. Plus the deterministic
append helper and the guest invariant (with a mode set).
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


def test_writer_and_matcher_share_one_format():
    # The note written and the string matched MUST be identical — both via
    # curriculum.done_note, no duplicated literal.
    note = curriculum.done_note("english", "animals")
    assert note == "đã học: english:animals"
    # The matcher (load_topic) detects exactly this note.
    assert curriculum._topic_done(f"Some summary. {note}", "english", "animals")


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

    # First session: no memory → first topic.
    t1 = curriculum.load_topic("english", "")
    assert t1["id"] == "animals"

    # The session writes the done-note (what _with_done_notes appends).
    memory = gemini_session._with_done_notes(
        "Bé thích con vật.", "", curriculum.done_note("english", t1["id"])
    )
    assert curriculum.done_note("english", "animals") in memory

    # Next session in the SAME mode → loader skips the done topic → advances.
    t2 = curriculum.load_topic("english", memory)
    assert t2["id"] == "food"


def test_with_done_notes_helper():
    # Appends on its own line; idempotent; no-op when empty.
    assert gemini_session._with_done_notes("abc", "", "") == "abc"
    out = gemini_session._with_done_notes("abc", "", "đã học: english:animals")
    assert out == "abc\nđã học: english:animals"
    # Idempotent — appending the same note again doesn't duplicate it.
    assert gemini_session._with_done_notes(out, "", "đã học: english:animals") == out
    # Empty prior summary + empty new summary → just the note.
    assert gemini_session._with_done_notes("", "", "đã học: x:y") == "đã học: x:y"


def test_prior_markers_carried_forward_when_model_drops_them():
    # M1: the summarizer rewrote the prose and DROPPED the prior "đã học:" line.
    # _with_done_notes must re-assert it deterministically so done-state survives
    # re-summarization (else a finished topic would be re-served next session).
    prior = "Bé thích con vật.\nđã học: english:animals"
    rewritten = "Bé thích con vật và đồ ăn."  # model dropped the marker
    out = gemini_session._with_done_notes(
        rewritten, prior, curriculum.done_note("english", "food")
    )
    # Both the old and the new topic remain marked done, each once, on own lines.
    assert curriculum._topic_done(out, "english", "animals")
    assert curriculum._topic_done(out, "english", "food")
    assert out.count("đã học: english:animals") == 1
    assert out.count("đã học: english:food") == 1


def test_prefix_topic_id_not_a_false_positive():
    # M2: a longer id ("foods") recorded done must NOT mark a shorter id ("food")
    # as done. Whole-line match (not bare substring) prevents the prefix collision.
    mem = f"Bé học rồi.\n{curriculum.done_note('english', 'foods')}"
    assert curriculum._topic_done(mem, "english", "foods")
    assert not curriculum._topic_done(mem, "english", "food")


def test_free_chat_writes_no_done_note():
    # No mode → run_session passes done_note="" → summary is untouched by the note.
    assert gemini_session._with_done_notes("Bé thích Elsa.", "", "") == "Bé thích Elsa."
    # And load_topic on free chat is None regardless of memory.
    assert curriculum.load_topic(None, "đã học: english:animals") is None
