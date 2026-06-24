"""Learning-mode plumbing tests: mode parsing + the prompt builder seam.

The hard requirement is BACKWARD COMPATIBILITY: with no mode, the system prompt
must be exactly what free chat produced before this feature, so nothing regresses
for existing users / old app builds.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import learning_modes  # noqa: E402
from child_profile import ChildProfile  # noqa: E402
from gemini_session_config import build_system_prompt  # noqa: E402

_CHILD = ChildProfile(
    profile_id="c1", name="Vy", age=5, interests=["khủng long"], gender="girl"
)


def _legacy_prompt(profile, memory_text=""):
    """Reconstruct the pre-feature prompt (persona + profile + memory) to assert
    the no-mode path is byte-identical.

    NOTE: this mirrors the builder's base assembly. To avoid the two drifting in
    lockstep (which would mask a real prompt change), `test_no_mode_has_no_mode_markers`
    independently asserts the free-chat prompt contains NONE of the mode artifacts —
    an assertion derived from the mode strings, not from this reconstruction.
    """
    import gemini_session_config as cfg

    parts = [cfg._BASE_SYSTEM_PROMPT, "", profile.to_prompt_text()]
    if memory_text.strip():
        parts += [
            "",
            "Điều bạn còn nhớ về bé / What you remember about the child:",
            memory_text.strip(),
            "Hãy dùng những điều này một cách tự nhiên, ấm áp khi hợp lý. "
            "Use these naturally and warmly when it fits.",
        ]
    return "\n".join(parts) + "\n"


def test_parse_mode():
    assert learning_modes.parse_mode("english") == "english"
    assert learning_modes.parse_mode("science") == "science"
    # Free chat: None, empty, "chat" sentinel, or anything unknown.
    assert learning_modes.parse_mode(None) is None
    assert learning_modes.parse_mode("") is None
    assert learning_modes.parse_mode("chat") is None
    assert learning_modes.parse_mode("math") is None  # deferred subject
    # Retired mode: old app builds may still send ?mode=stories → free chat.
    assert learning_modes.parse_mode("stories") is None


def test_no_mode_prompt_is_unchanged():
    # The whole point: free chat (no mode) == the legacy prompt, byte for byte.
    assert build_system_prompt(_CHILD) == _legacy_prompt(_CHILD)
    assert build_system_prompt(_CHILD, "Vy thích Elsa.") == _legacy_prompt(
        _CHILD, "Vy thích Elsa."
    )
    # An unknown mode also degrades to free chat (no script appended).
    assert build_system_prompt(_CHILD, mode="math") == _legacy_prompt(_CHILD)


def test_mode_prompt_includes_its_script():
    for mode, marker in [
        ("english", "HỌC TIẾNG ANH"),
        ("science", "KHOA HỌC"),
    ]:
        p = build_system_prompt(_CHILD, mode=mode)
        assert marker in p, f"{mode} script missing"
        # Persona + profile are still present (mode augments, doesn't replace).
        assert "người bạn ảo" in p and "Vy" in p


def test_scripts_enforce_elicit_wait():
    """The defining v2 behavior: both learning scripts must give an explicit,
    hard ASK-THEN-WAIT instruction so the model elicits + waits instead of
    monologuing. We assert the instruction is PRESENT (the model actually
    obeying it is the on-device gate, not a unit test)."""
    for mode in (learning_modes.ENGLISH, learning_modes.SCIENCE):
        script = learning_modes.leading_script(mode)
        # Blunt WAIT wording (shared preamble) + the elicit verb.
        assert "CHỜ" in script and "WAIT" in script, f"{mode}: no WAIT"
        assert "DỪNG" in script and "STOP" in script, f"{mode}: no STOP"
    # English elicits a repeat; science elicits a guess — mode-specific.
    eng = learning_modes.leading_script(learning_modes.ENGLISH)
    assert "NHẮC" in eng and "REPEAT" in eng
    sci = learning_modes.leading_script(learning_modes.SCIENCE)
    assert "ĐOÁN" in sci and "GUESS" in sci


def test_scripts_carry_spaced_repetition():
    for mode in (learning_modes.ENGLISH, learning_modes.SCIENCE):
        script = learning_modes.leading_script(mode)
        assert "Ôn lại" in script and "Review first" in script, f"{mode}: no review"


def test_age_band_line_bands():
    young = learning_modes.age_band_line(4)
    young6 = learning_modes.age_band_line(6)
    old7 = learning_modes.age_band_line(7)
    old10 = learning_modes.age_band_line(10)
    # Boundary 4/6 → YOUNG band; 7/10 → OLDER band.
    assert "YOUNG" in young and "YOUNG" in young6
    assert "OLDER" in old7 and "OLDER" in old10
    assert young == young6 and old7 == old10  # same band → same line
    assert young != old7  # the two bands differ
    # Never empty, even out of range (clamps to nearest band).
    assert learning_modes.age_band_line(3) and learning_modes.age_band_line(11)
    assert "YOUNG" in learning_modes.age_band_line(3)
    assert "OLDER" in learning_modes.age_band_line(11)


def test_age_band_present_in_mode_prompt_absent_in_free_chat():
    band = learning_modes.age_band_line(_CHILD.age)
    # Present when a learning mode is active...
    assert band in build_system_prompt(_CHILD, mode="english")
    assert band in build_system_prompt(_CHILD, mode="science")
    # ...absent in free chat (byte-identical invariant).
    assert band not in build_system_prompt(_CHILD)
    assert band not in build_system_prompt(_CHILD, mode="math")  # unknown → free


def test_lesson_block_appended_when_present():
    p = build_system_prompt(
        _CHILD, mode="english", lesson="con chó = dog; con mèo = cat"
    )
    assert "Nội dung bài hôm nay" in p
    assert "con chó = dog" in p
    # No lesson → no lesson header.
    p2 = build_system_prompt(_CHILD, mode="english")
    assert "Nội dung bài hôm nay" not in p2


def test_leading_script_empty_for_chat():
    assert learning_modes.leading_script(None) == ""
    assert learning_modes.leading_script("chat") == ""
    assert learning_modes.leading_script("english") != ""


def test_no_mode_has_no_mode_markers():
    """Drift-proof backstop: the free-chat prompt must contain NO mode artifact.

    Derived from the mode strings + the lesson header, NOT from _legacy_prompt —
    so even if the base assembly and the reconstruction drifted together, this
    still catches a mode/lesson block leaking into free chat.
    """
    free = build_system_prompt(_CHILD, "Vy thích Elsa.")
    for mode in learning_modes.VALID_MODES:
        assert learning_modes.leading_script(mode) not in free
    assert "Nội dung bài hôm nay" not in free  # no lesson header in free chat
