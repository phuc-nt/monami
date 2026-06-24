"""Learning modes: the optional structured activities a session can run.

A session is normally free chat. If the client connects with `?mode=<mode>`, the
companion leads a structured activity instead — English vocabulary or a
curious-science "why". This module is the SINGLE source of truth for the mode
strings (the app mirrors them) + each mode's *leading script* (the pedagogy
framing that's prepended to the system prompt).

The actual lesson content (which word set / question) comes from the JSON
curriculum (see `curriculum.py`) and is passed in separately as `lesson` text;
this module only owns the per-mode *framing*, not the content.

Backward compatible: an unknown/absent mode resolves to None = free chat (today's
behavior), so old app builds and mode-less connects are unaffected. In particular
the retired `stories` mode now resolves to free chat — old builds that still send
`?mode=stories` degrade gracefully, never crash.
"""

from __future__ import annotations

# The two structured learning modes. The Flutter app mirrors these exact
# strings (see app/lib/learning_mode.dart); keep them in sync.
ENGLISH = "english"
SCIENCE = "science"

VALID_MODES: frozenset[str] = frozenset({ENGLISH, SCIENCE})


def parse_mode(raw: str | None) -> str | None:
    """Resolve a raw query-param value to a known mode, or None (= free chat).

    None covers: no param, empty string, the "chat" sentinel, or any unknown
    value — all mean "free chat", the default unchanged behavior.
    """
    if raw and raw in VALID_MODES:
        return raw
    return None


# Shared framing: in any learning mode the companion LEADS the activity — it
# starts the lesson itself rather than waiting, AND it teaches by ELICITING
# (asking the child to produce / guess) then WAITING for the answer, instead of
# monologuing. This is the one thing free chat can't reliably do; it's what makes
# a mode worth more than just answering the same question in free chat. The WAIT
# is stated bluntly and repeated because the live model tends to keep talking.
_LEAD_PREAMBLE = (
    "Bạn đang ở chế độ HỌC. Hãy CHỦ ĐỘNG dẫn dắt hoạt động hôm nay ngay từ đầu —\n"
    "đừng chỉ chờ bé hỏi. Nếu bé nói sang chuyện khác, trả lời thật NGẮN rồi nhẹ\n"
    "nhàng quay lại bài. Giữ vui vẻ, không ép.\n"
    "QUY TẮC QUAN TRỌNG NHẤT — HỎI RỒI CHỜ: mỗi lượt chỉ đưa RA MỘT việc nhỏ\n"
    "(một từ, hoặc một câu hỏi), rồi DỪNG LẠI và CHỜ bé trả lời. KHÔNG nói tiếp,\n"
    "KHÔNG đọc cả danh sách, KHÔNG tự trả lời thay bé. Im lặng chờ là tốt. Chỉ\n"
    "nói tiếp SAU KHI bé đã đáp lại.\n"
    "You are in a LEARNING mode. Take the LEAD and start today's activity yourself\n"
    "from the beginning — don't just wait for the child to ask. If the child drifts,\n"
    "answer very briefly, then gently steer back. Keep it fun, never pushy.\n"
    "MOST IMPORTANT RULE — ASK, THEN WAIT: each turn give just ONE small thing\n"
    "(one word, or one question), then STOP and WAIT for the child to answer. Do\n"
    "NOT continue, do NOT read the whole list, do NOT answer for the child. Waiting\n"
    "in silence is good. Only go on AFTER the child has responded.\n"
)

# Spaced-repetition nudge, shared by both modes. The model reads the per-child
# memory (already in the prompt) which may carry "đã học: <mode>:<id>" notes from
# past sessions. This line tells it to warm up by briefly revisiting a prior topic
# before the new one — no new code path; it just leans on memory_text being there.
_SPACED_REP_LINE = (
    "- Ôn lại trước: nếu phần GHI NHỚ cho thấy bé ĐÃ HỌC một chủ đề của chế độ này\n"
    "  rồi, hãy mở đầu bằng ~30 giây ôn nhanh chủ đề cũ đó (hỏi bé nhớ gì) rồi mới\n"
    "  sang bài mới.\n"
    "  Review first: if the memory shows the child already learned a topic in this\n"
    "  mode, open with a quick ~30s review of that old topic (ask what they "
    "remember) before the new one."
)

# Per-mode leading script: short, bilingual framing for how the companion should
# LEAD + ELICIT. Kept concise so it doesn't bloat the system prompt.
_SCRIPTS: dict[str, str] = {
    ENGLISH: _LEAD_PREAMBLE + (
        "\nChế độ HỌC TIẾNG ANH / English-learning mode:\n"
        "- Giới thiệu chủ đề hôm nay thật ngắn, rồi dạy TỪNG TỪ MỘT.\n"
        "  Introduce today's topic briefly, then teach the words ONE AT A TIME.\n"
        "- Với mỗi từ: nói từ tiếng Anh + nghĩa tiếng Việt MỘT LẦN, rồi bảo bé NHẮC\n"
        "  LẠI và DỪNG, CHỜ bé nói. KHÔNG sang từ kế khi bé chưa thử.\n"
        "  For each word: say the English word + Vietnamese meaning ONCE, then ask "
        "the child to REPEAT and STOP, WAIT for them. Do NOT move to the next word "
        "until they try.\n"
        "- Bé nói đúng thì khen; sai thì nói lại nhẹ nhàng một lần rồi mời thử lại.\n"
        "  If right, praise; if wrong, gently say it once more and invite another try.\n"
        + _SPACED_REP_LINE
    ),
    SCIENCE: _LEAD_PREAMBLE + (
        "\nChế độ KHOA HỌC / Science mode:\n"
        "- Nêu hiện tượng hôm nay bằng câu NGẮN, rồi hỏi bé ĐOÁN 'vì sao' TRƯỚC.\n"
        "  State today's phenomenon in a SHORT sentence, then ask the child to GUESS "
        "'why' FIRST.\n"
        "- DỪNG và CHỜ bé đoán. KHÔNG giải thích trước khi bé đoán.\n"
        "  STOP and WAIT for the guess. Do NOT explain before the child guesses.\n"
        "- Sau khi bé đoán, khen ý đó, rồi giải thích ĐƠN GIẢN, nối lại với điều bé\n"
        "  vừa đoán. Kết bằng một câu hỏi gợi tò mò để bé đáp tiếp.\n"
        "  After the guess, praise it, then explain SIMPLY, tying back to what the "
        "child guessed. End with a curious follow-up question for them to answer.\n"
        "- Luôn an toàn, chính xác ở mức cơ bản, không làm bé sợ.\n"
        "  Always safe, basically accurate, never scary.\n"
        + _SPACED_REP_LINE
    ),
}


def leading_script(mode: str | None) -> str:
    """The pedagogy framing for a mode ("" for free chat / unknown)."""
    resolved = parse_mode(mode)
    return _SCRIPTS.get(resolved, "") if resolved else ""


# Age scaffolding: a single bilingual line that tunes difficulty to the child's
# age. Two bands (4-6 / 7-10) chosen in planning; ages outside the learning range
# clamp to the nearest band (a 3-year-old gets the easiest, an 11-year-old the
# hardest) rather than dropping the guidance. Pure + unit-testable like parse_mode;
# the prompt builder appends it ONLY when a learning mode is active, so free chat
# stays byte-identical.
def age_band_line(age: int) -> str:
    """One-line bilingual difficulty hint for the child's age (always non-empty).

    Band boundary: 4-6 = youngest, 7+ = older. Below 4 clamps to the young band,
    so the helper never returns "" (an absent line would weaken scaffolding for an
    out-of-range age). The two bands match the 4-6 / 7-10 design.
    """
    if age <= 6:
        return (
            "Độ tuổi của bé: NHỎ (4-6). Dùng câu RẤT NGẮN, mỗi lượt một việc, lặp\n"
            "lại nhiều, chưa cần ghép câu. Bắt đầu thật dễ rồi mới khó dần.\n"
            "Child's age: YOUNG (4-6). Use VERY short sentences, one thing per turn,\n"
            "lots of repetition, no sentence-building yet. Start very easy, then "
            "ramp up."
        )
    return (
        "Độ tuổi của bé: LỚN HƠN (7-10). Có thể ghép cụm thành câu, hỏi 'vì sao',\n"
        "thêm bước, từ vựng rộng hơn. Vẫn bắt đầu dễ rồi khó dần trong buổi học.\n"
        "Child's age: OLDER (7-10). Can build phrases into sentences, ask 'why',\n"
        "add steps, wider vocabulary. Still start easy and ramp up within the "
        "session."
    )
