"""Learning modes: the optional structured activities a session can run.

A session is normally free chat. If the client connects with `?mode=<mode>`, the
companion leads a structured activity instead — English vocabulary, storytelling,
or a curious-science "why". This module is the SINGLE source of truth for the mode
strings (the app mirrors them) + each mode's *leading script* (the pedagogy
framing that's prepended to the system prompt).

The actual lesson content (which word set / story / question) comes from the JSON
curriculum (see `curriculum.py`) and is passed in separately as `lesson` text;
this module only owns the per-mode *framing*, not the content.

Backward compatible: an unknown/absent mode resolves to None = free chat (today's
behavior), so old app builds and mode-less connects are unaffected.
"""

from __future__ import annotations

# The three structured learning modes. The Flutter app mirrors these exact
# strings (see app/lib/learning_mode.dart); keep them in sync.
ENGLISH = "english"
STORIES = "stories"
SCIENCE = "science"

VALID_MODES: frozenset[str] = frozenset({ENGLISH, STORIES, SCIENCE})


def parse_mode(raw: str | None) -> str | None:
    """Resolve a raw query-param value to a known mode, or None (= free chat).

    None covers: no param, empty string, the "chat" sentinel, or any unknown
    value — all mean "free chat", the default unchanged behavior.
    """
    if raw and raw in VALID_MODES:
        return raw
    return None


# Per-mode leading script: short, bilingual, age-5 framing for how the companion
# should lead the activity. Kept concise so it doesn't bloat the system prompt.
_SCRIPTS: dict[str, str] = {
    ENGLISH: (
        "Chế độ HỌC TIẾNG ANH / English-learning mode:\n"
        "- Dẫn dắt bé làm quen vài từ tiếng Anh trong bài hôm nay một cách vui vẻ.\n"
        "  Gently lead the child through a few English words from today's lesson.\n"
        "- Nói từ tiếng Anh, rồi nghĩa tiếng Việt, mời bé NHẮC LẠI; khen khi bé thử.\n"
        "  Say the English word, then the Vietnamese meaning, invite the child to "
        "REPEAT; praise every attempt.\n"
        "- Lặp lại từ vài lần qua trò chuyện để bé nhớ. Đừng ép, giữ nhẹ nhàng.\n"
        "  Repeat the words a few times through play so they stick. Never push."
    ),
    STORIES: (
        "Chế độ KỂ CHUYỆN / Storytelling mode:\n"
        "- Kể câu chuyện ngắn hôm nay bằng giọng ấm áp, câu NGẮN, dễ hiểu cho bé 5 tuổi.\n"
        "  Tell today's short story warmly, in SHORT simple sentences for a 5-year-old.\n"
        "- Thỉnh thoảng dừng hỏi bé nghĩ gì / đoán điều gì xảy ra tiếp.\n"
        "  Pause now and then to ask what the child thinks or what happens next.\n"
        "- Kết thúc bằng một ý nghĩa nhẹ nhàng, tích cực.\n"
        "  End with a gentle, positive takeaway."
    ),
    SCIENCE: (
        "Chế độ VÌ SAO / Curious-science mode:\n"
        "- Trả lời câu hỏi 'tại sao' hôm nay ở mức ĐƠN GIẢN, dễ hiểu cho bé 5 tuổi.\n"
        "  Answer today's 'why' question SIMPLY, at a 5-year-old's level.\n"
        "- Dùng ví dụ gần gũi; mời bé hỏi thêm; khơi tò mò chứ không giảng dài.\n"
        "  Use familiar examples; invite more questions; spark curiosity, don't "
        "lecture.\n"
        "- Luôn an toàn, chính xác ở mức cơ bản, không làm bé sợ.\n"
        "  Always safe, basically accurate, never scary."
    ),
}


def leading_script(mode: str | None) -> str:
    """The pedagogy framing for a mode ("" for free chat / unknown)."""
    resolved = parse_mode(mode)
    return _SCRIPTS.get(resolved, "") if resolved else ""
