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
    assert learning_modes.parse_mode("stories") == "stories"
    assert learning_modes.parse_mode("science") == "science"
    # Free chat: None, empty, "chat" sentinel, or anything unknown.
    assert learning_modes.parse_mode(None) is None
    assert learning_modes.parse_mode("") is None
    assert learning_modes.parse_mode("chat") is None
    assert learning_modes.parse_mode("math") is None  # deferred subject


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
        ("stories", "KỂ CHUYỆN"),
        ("science", "VÌ SAO"),
    ]:
        p = build_system_prompt(_CHILD, mode=mode)
        assert marker in p, f"{mode} script missing"
        # Persona + profile are still present (mode augments, doesn't replace).
        assert "người bạn ảo" in p and "Vy" in p


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
