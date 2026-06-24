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


# Shared framing: in any learning mode the companion LEADS the activity — it
# starts the lesson itself rather than waiting, and gently steers back if the child
# drifts. (E2E showed that without this, the model just answers the child's
# question like free chat instead of teaching.)
_LEAD_PREAMBLE = (
    "Bạn đang ở chế độ HỌC. Hãy CHỦ ĐỘNG dẫn dắt hoạt động hôm nay ngay từ đầu —\n"
    "đừng chỉ chờ bé hỏi. Nếu bé nói sang chuyện khác, trả lời thật NGẮN rồi nhẹ\n"
    "nhàng quay lại bài. Giữ vui vẻ, không ép.\n"
    "You are in a LEARNING mode. Take the LEAD and start today's activity yourself\n"
    "from the beginning — don't just wait for the child to ask. If the child drifts,\n"
    "answer very briefly, then gently steer back to the activity. Keep it fun,\n"
    "never pushy.\n"
)

# Per-mode leading script: short, bilingual, age-5 framing for how the companion
# should lead the activity. Kept concise so it doesn't bloat the system prompt.
_SCRIPTS: dict[str, str] = {
    ENGLISH: _LEAD_PREAMBLE + (
        "\nChế độ HỌC TIẾNG ANH / English-learning mode:\n"
        "- Mở đầu bằng việc giới thiệu chủ đề hôm nay, rồi dạy từng từ tiếng Anh.\n"
        "  Open by introducing today's topic, then teach the English words one by one.\n"
        "- Nói từ tiếng Anh, rồi nghĩa tiếng Việt, mời bé NHẮC LẠI; khen khi bé thử.\n"
        "  Say the English word, then the Vietnamese meaning, invite the child to "
        "REPEAT; praise every attempt.\n"
        "- Lặp lại từ vài lần qua trò chuyện để bé nhớ. Đừng ép, giữ nhẹ nhàng.\n"
        "  Repeat the words a few times through play so they stick. Never push."
    ),
    STORIES: _LEAD_PREAMBLE + (
        "\nChế độ KỂ CHUYỆN / Storytelling mode:\n"
        "- Bắt đầu kể luôn câu chuyện ngắn hôm nay bằng giọng ấm áp, câu NGẮN.\n"
        "  Start telling today's short story right away, warmly, in SHORT sentences.\n"
        "- Thỉnh thoảng dừng hỏi bé nghĩ gì / đoán điều gì xảy ra tiếp.\n"
        "  Pause now and then to ask what the child thinks or what happens next.\n"
        "- Kết thúc bằng một ý nghĩa nhẹ nhàng, tích cực.\n"
        "  End with a gentle, positive takeaway."
    ),
    SCIENCE: _LEAD_PREAMBLE + (
        "\nChế độ VÌ SAO / Curious-science mode:\n"
        "- Mở đầu bằng câu hỏi 'tại sao' hôm nay, rồi giải thích ĐƠN GIẢN cho bé.\n"
        "  Open with today's 'why' question, then explain it SIMPLY for the child.\n"
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
