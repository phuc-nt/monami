# Brainstorm — Learning Modes v2: 2 mode chuyên biệt, voice-first

**Date:** 2026-06-24
**Status:** Approved → next `/mk:plan`
**Predecessor:** Learning Modes v1 (4/4 done, shipped TestFlight 1.0.0 build 3)

## Problem statement

Learning Modes v1 có 3 mode (english/stories/science). Vấn đề user nêu:
- Free-chat "Trò chuyện" CŨNG mô phỏng được english + science (model tự trả lời câu hỏi
  tiếng Anh / câu hỏi khoa học) → 2 mode chuyên biệt CHƯA tạo giá trị giáo dục khác biệt rõ.
- Cần: CHỈ bằng giọng nói (voice-only, không hình ảnh, robot face giữ nguyên) mà mang giá
  trị giáo dục CAO HƠN cho bé **4-10 tuổi** (dải rộng hơn v1, trước nhắm 5 tuổi).

3 thay đổi của phase:
1. BỎ mode "stories"/Kể chuyện hoàn toàn.
2. Đổi label "Vì sao?" → "Khoa học" (mode key `science` giữ nguyên).
3. (LÕI) Nâng english + science chuyên biệt hơn hẳn free-chat.

## Diagnosis — vì sao 2 mode v1 "yếu"

Kiến trúc v1 = leading script (khung sư phạm) + 1 topic JSON nhồi vào system prompt. Cả hai
chỉ là *nội dung để model nói ra*. Free-chat nói y hệt được nếu bé hỏi.

Cái free-chat KHÔNG làm = **vòng lặp tương tác có cấu trúc**: model hỏi → chờ bé đáp →
đánh giá → sửa/khen → củng cố → tăng độ khó. Đó là nơi sinh giá trị giáo dục (active recall
+ scaffolding + spaced repetition). Free-chat trả lời ngay; mode học phải GIỮ câu hỏi mở và CHỜ.

## Locked decisions (từ user)

- **Độ khó:** dùng `age` có sẵn trong `ChildProfile` (đã render vào prompt qua
  `to_prompt_text()`). Backend chèn age-band → model tự chỉnh độ dài câu/từ vựng/độ sâu.
  KISS, không thêm UI, không curriculum biến thể theo tuổi.
- **Cơ chế giáo dục cốt lõi (3):** Active recall + Spaced repetition + Scaffolding.
  ("Sửa lỗi & khen" là hệ quả tự nhiên của active recall, không tách trục riêng.)
- **Nội dung:** mở rộng **4-5 topic/mode** (AI generate, user review).
- **Next step:** `/mk:plan`.

## Design

### A. Thay đổi dễ (1 & 2) — mechanical
| Việc | Backend | App |
|------|---------|-----|
| Bỏ stories | Xóa `STORIES` khỏi `learning_modes.py` + `VALID_MODES` + `_SCRIPTS`; xóa `_render_story` trong `curriculum.py`; xóa `curriculum/stories.json` | Xóa `LearningMode.stories` (enum + 3 switch) trong `learning_mode.dart` |
| Rename | không đổi (key `science` giữ) | đổi `label` `'Vì sao?'`→`'Khoa học'` |

Backward-compat: app cũ gửi `?mode=stories` → `parse_mode`→None → free-chat (an toàn).

### B. Lõi — biến "nội dung" thành "vòng lặp dạy học"

**B1. Active recall — viết lại leading script thành nhịp ELICIT–WAIT–RESPOND bắt buộc**
- TA: nói 1 từ → HỎI bé nói lại → DỪNG chờ → đúng: khen + dùng từ trong 1 câu ngắn / sai:
  nói lại chậm, mời thử lại. KHÔNG đọc liền cả list. 1 lượt = 1 từ + 1 lần bé đáp.
- KH: nêu hiện tượng → HỎI bé đoán "vì sao" TRƯỚC → chờ → mới giải thích, nối vào điều bé đoán.

**B2. Scaffolding theo age** (backend chèn 1 dòng dựa `profile.age`):
- 4-6: câu cực ngắn, 1 từ/khái niệm/lượt, lặp nhiều, không bắt ghép câu.
- 7-10: ghép cụm→câu, hỏi "con giải thích vì sao", nối nhiều bước, từ vựng rộng.
- Trong buổi cũng dễ→khó: TA từ đơn→cụm→câu; KH hiện tượng→"vì sao"→"đoán bước tiếp".

**B3. Spaced repetition** — tận dụng memory đã có (`done_note(mode, topic_id)`):
- Đầu buổi nếu memory có topic đã học mode này → model ôn nhanh ~30s (1-2 mục cũ, hỏi bé
  còn nhớ) TRƯỚC khi vào topic mới. 1 dòng script + đọc done_note cũ. Không data model mới.

### C. Curriculum schema v2 — thêm "thang bậc", field TÙY CHỌN (backward compatible)
- english topic thêm `elicit_vi` (gợi câu hỏi recall). Giữ `words`/`sentence_*`.
- science topic thêm `predict_vi` (hỏi bé đoán TRƯỚC khi giải thích). Giữ `answer_vi`/`follow_up_vi`.
- `render_lesson` chỉ in thêm field nếu có. `_topic_done`/`load_topic`/`DONE_MARKER` KHÔNG đổi.
- Mở rộng lên 4-5 topic mỗi mode (AI generate → user review).

### D. KHÔNG làm (KISS)
- ❌ pronunciation scoring (native-audio không cho điểm âm vị tin cậy)
- ❌ thêm UI / WS param / đổi kiến trúc Gemini Live
- ❌ data model học tập riêng (vẫn per-child text memory)
- ❌ curriculum biến thể theo tuổi (model tự chỉnh theo age)

## Blast radius
- Backend: `learning_modes.py` (rewrite 2 script, xóa stories), `curriculum.py` (render field
  mới + xóa `_render_story`), `curriculum/english.json` + `science.json` (field mới + thêm topic),
  xóa `curriculum/stories.json`, chèn age-band vào prompt (verify `gemini_session_config.py`
  đã truyền profile — đã có).
- App: `learning_mode.dart` (xóa enum stories, đổi 1 label).
- Tests: cập nhật test chứa "stories"; thêm test script chứa nhịp elicit; giữ round-trip done-note;
  giữ guest-no-persist + byte-identical free-chat invariant.

## Risks
- **Model không tuân nhịp WAIT** (vẫn nói tuột) → cần verify trên device thật; script phải
  rất dứt khoát ("DỪNG, chờ bé trả lời, KHÔNG nói tiếp"). Đây là rủi ro lớn nhất, định nghĩa
  thành công của phase.
- **Latency** khi prompt dài thêm (age-band + field mới) → giữ lesson cap `_MAX_LESSON_CHARS`.
- **Dải tuổi rộng**: age-band 2 nhóm có thể chưa đủ cho cực biên (4 vs 10) → chấp nhận, model tự co giãn.

## Success criteria
- english/science mode chạy nhịp elicit-wait-respond (model hỏi & CHỜ, không tuột list) — verify device.
- Bỏ stories sạch (app + backend + JSON); app cũ gửi mode=stories vẫn về free-chat an toàn.
- Label "Khoa học" hiển thị; mode key science không đổi.
- 4-5 topic/mode; spaced-repetition ôn topic cũ đầu buổi khi memory có done-note.
- Guest vẫn KHÔNG persist; free-chat byte-identical; child docs cũ vẫn load.

## Open questions
- Ngưỡng age-band chính xác (4-6 / 7-10) hay 3 nhóm? → để plan chốt, default 2 nhóm.
- Số topic cuối: 4 hay 5? → plan/authoring quyết khi generate.
