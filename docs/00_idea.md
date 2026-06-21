# Brief: Người Bạn Số Song Ngữ cho 2 Bé 5 Tuổi

> Tài liệu bàn giao cho Claude Code. Cố ý giữ ở mức brief — mô tả bối cảnh, nhu cầu, lựa chọn nền tảng và yêu cầu phi chức năng cơ bản. Phần thiết kế chi tiết, scaffolding, system prompt, code khung… để Claude Code (với bộ công cụ đầy đủ hơn) tự khai triển.

---

## 1. Bối cảnh

Tôi có **2 con sinh đôi/cùng 5 tuổi** (mầm non). Tôi muốn **tự build một "người bạn số"** cho con — một nhân vật ảo trên app mà con có thể trò chuyện hằng ngày bằng giọng nói. Mục tiêu không phải dạy học chính quy, mà là tạo một **người bạn đồng hành vui vẻ, an toàn**, qua đó con được **làm quen tiếng Anh một cách tự nhiên** và thỏa trí tò mò.

Tôi chọn làm **app ảo** (không phải robot vật lý) vì dễ nâng cấp, tận dụng sẵn thiết bị, và kiểm soát hoàn toàn trải nghiệm + độ an toàn cho con.

---

## 2. Nhu cầu cốt lõi

- **Người bạn, không phải giáo viên.** Giọng thân thiện, kiên nhẫn, khích lệ, không phán xét. Nhớ tên con, sở thích, chuyện hôm qua → cảm giác như một người bạn thật.
- **Song ngữ Anh – Việt, linh hoạt.** Mặc định dùng ngôn ngữ con thoải mái; chêm/chuyển sang tiếng Anh một cách tự nhiên để con "thấm" dần. Không ép, không làm con nản.
- **Thoại là chính (voice-first).** Tương tác chủ yếu bằng nói chuyện hai chiều, độ trễ thấp để cảm giác tự nhiên. Trẻ 5 tuổi chưa đọc viết tốt nên giọng nói là kênh chính.
- **Hai hồ sơ riêng.** Mỗi bé một profile, một "trí nhớ" riêng (tránh lẫn tiến độ/sở thích giữa 2 con).
- **Phụ huynh kiểm soát được.** Giới hạn thời lượng dùng, xem lại con đã nói chuyện gì, an tâm về nội dung.

---

## 3. Nhóm tính năng thoại (phù hợp tuổi 5)

Định hình theo "học mà chơi", không phải môn học chính quy:

- **Tiếng Anh qua chơi:** từ vựng đơn giản, câu ngắn, bài hát, trò chuyện, làm quen phát âm.
- **Tiền-toán học:** đếm số, nhận biết hình khối, màu sắc, so sánh nhiều/ít — qua trò chơi bằng giọng nói.
- **Khoa học tò mò:** trả lời các câu "tại sao" về động vật, thiên nhiên, cơ thể… ở mức kể chuyện đơn giản, dễ hiểu.
- **Kể chuyện & đố vui:** kể chuyện theo yêu cầu, câu đố, trò chơi tương tác bằng lời.
- **Bạn tâm tình:** chia sẻ cảm xúc, thói quen tốt, động viên — phần "đồng hành".
- **Hỏi đáp kiến thức chung:** trả lời thắc mắc của con ở mức phù hợp lứa tuổi (có kiểm soát an toàn).

*Lưu ý cho Claude Code:* Toán/khoa học ở tuổi này nếu cần minh hoạ thì dùng màn hình/hình ảnh hỗ trợ, nhưng **ưu tiên trải nghiệm thoại trước**; phần hình ảnh để giai đoạn sau.

---

## 4. Lựa chọn tech cơ bản (đã chốt hướng)

| Lớp | Lựa chọn | Vì sao |
|---|---|---|
| App cross-platform (iOS + Android) | **Flutter** | Một codebase, UI/nhân vật đồng nhất 2 nền |
| Nhân vật | **Rive** (animation + lip-sync) | Người bạn dễ thương, mấp máy miệng theo lời |
| Truyền realtime | **LiveKit (WebRTC)** | Lớp thoại realtime tốt nhất, chịu mạng nhà chập chờn; mã nguồn mở, không lock-in |
| Agent / orchestration | **LiveKit Agents (Python)** | Điều phối hội thoại, guardrail, nhớ ngữ cảnh |
| Model thoại | **Gemini Live (native audio)** | Speech-to-speech một lượt, song ngữ EN/VN, độ trễ thấp, chi phí rẻ |
| Dữ liệu / hồ sơ / trí nhớ | **Supabase** (hoặc Cloud SQL) | Lưu 2 hồ sơ, tiến độ, lịch sử hội thoại |
| Chấm phát âm tiếng Anh (tùy chọn, sau) | **Azure Pronunciation Assessment** | Khi muốn nâng phần luyện nói |

---

## 5. Lựa chọn infra cơ bản

- **Vùng:** GCP **`asia-southeast1` (Singapore)** cho toàn bộ — đặt agent **cùng vùng** với Gemini Live để độ trễ thấp nhất cho người dùng tại Việt Nam.
- **MVP:** dùng **LiveKit Cloud** (đỡ vận hành) + agent chạy trên **GCP Cloud Run** (bật min-instance để tránh cold start).
- **Về sau:** có thể self-host LiveKit trên GCP Singapore để tối ưu chi phí/kiểm soát (vì mã nguồn mở).
- Auth + asset: Supabase Auth; CDN (Cloudflare) nếu cần host asset nhân vật.

---

## 6. Yêu cầu phi chức năng (NFR) cơ bản

- **An toàn trẻ em — ưu tiên số 1.** Lọc nội dung nhiều lớp trước khi bot nói; bật safety mức nghiêm; nội dung luôn phù hợp trẻ 5 tuổi. Không thoả hiệp.
- **Độ trễ thấp.** Mục tiêu cảm giác hội thoại tự nhiên (dưới ~1 giây từ lúc con dứt lời). Tinh chỉnh để **không cướp lời** trẻ nói chậm/ngập ngừng.
- **Song ngữ mượt.** Chuyển ngữ EN/VN trong cùng cuộc trò chuyện, không gãy.
- **Đa hồ sơ.** Tách bạch dữ liệu/trí nhớ giữa 2 bé.
- **Quyền riêng tư trẻ em.** Thu thập tối thiểu, dữ liệu của con được bảo vệ; phụ huynh có quyền xem/xoá.
- **Kiểm soát thời lượng.** Giới hạn thời gian dùng mỗi ngày (quan trọng với tuổi 5).
- **Độ tin cậy & xử lý mất mạng.** Khi rớt mạng, app báo nhẹ nhàng và phục hồi phiên, không làm con hoảng.
- **Chi phí thấp.** Dùng cá nhân cho 2 bé → tối ưu để chỉ vài USD–chục USD/tháng.
- **Giọng & nhân vật thân thiện.** Tông giọng ấm, vui; nhân vật biểu cảm.

---

## 7. Ghi chú bàn giao cho Claude Code

Bản brief này cố ý **không đi sâu thiết kế**. Khi tiếp nhận, Claude Code có thể chủ động:

- Dựng kiến trúc chi tiết, sơ đồ luồng, cấu trúc thư mục.
- Viết **system prompt song ngữ "người bạn cho trẻ 5 tuổi"** + lớp guardrail an toàn.
- Scaffold app Flutter + tích hợp LiveKit client + agent Python + plugin Gemini Live (Singapore).
- Thiết kế schema Supabase cho 2 hồ sơ + trí nhớ + kiểm soát phụ huynh.
- Lập lộ trình MVP → hoàn thiện, và checklist tối ưu độ trễ.

**Stack lõi tóm tắt:** Flutter · LiveKit (WebRTC) · LiveKit Agents (Python) · Gemini Live (Vertex AI, Singapore) · Supabase — tất cả co-locate tại `asia-southeast1`, ưu tiên trải nghiệm thoại, an toàn trẻ em, song ngữ Anh–Việt, cho 2 bé 5 tuổi.