---
type: brainstorm-design-summary
date: 2026-06-21
slug: bilingual-voice-companion-kids
status: approved
source: docs/00_idea.md
---

# Brainstorm Summary — "Người Bạn Số" Voice Companion cho 2 bé 5 tuổi

> Design đã được user duyệt. Kết quả brainstorm từ `docs/00_idea.md`. Sacrifice grammar for concision.

## 1. Problem Statement & Requirements

App thoại song ngữ EN-VN, **người-bạn-không-phải-giáo-viên**, cho 2 bé sinh đôi 5 tuổi.
Chạy thật cho con NGAY; kiến trúc sạch để mở lên sản phẩm sau (CHƯA làm compliance work, chỉ ghi chú).

**MVP scope (chốt):** voice loop tối giản — trò chuyện 2 chiều song ngữ + nhân vật Rive + 2 profile + trí nhớ cơ bản + **hard time-limit/ngày**.
**Loại khỏi MVP (→ phase sau):** pronunciation scoring, songs, structured games, parent transcript dashboard, hình ảnh toán/khoa học, compliance/multi-tenant.

**Ưu tiên (chốt):** An toàn nội dung → Độ trễ tự nhiên (<~1s) → Trí nhớ cá nhân hoá.

**Decisions chốt với user:**
- Phương án kiến trúc: **B (LiveKit + Gemini Live)** + bắt buộc **Phase 0 spike test** trước.
- Agent hosting: **GCE e2-micro always-on (~$7/mo)** — không cold-start.
- Storage: **full text transcript/phiên** (enable parent dashboard sau) — **KHÔNG lưu audio**.
- Auth: **PIN khoá màn hình phụ huynh** (không auth thật cho MVP).
- Safety: **Gemini safety strict + system prompt chặt + topic blocklist** (không LLM judge → giữ độ trễ thấp).

## 2. Evaluated Approaches

| | A. Direct Gemini Live | **B. LiveKit + Gemini Live ⭐** | C. Pipeline STT→LLM→TTS |
|---|---|---|---|
| Luồng | Flutter → Gemini WS | Flutter → LiveKit → Agent(Py) → Gemini Live | Flutter → LiveKit → Deepgram + Gemini Flash + ElevenLabs |
| Độ trễ | Thấp nhất | Thấp (+1 hop) | ~1-1.2s |
| Không cướp lời trẻ | ❌ bug cutoff #2117, không chỉnh | ✅ turn-detector tunable | ✅ tunable |
| Mạng nhà chập chờn | ❌ no failover | ✅ LiveKit edge | ✅ LiveKit edge |
| Trí nhớ | chỉ system prompt | ✅ agent inject trước session | ✅ linh hoạt |
| Chi phí/tháng | ~$1 | ~$40 model + ~$7-10 infra | ~$25-35 |
| Phức tạp | Thấp | Trung bình | Cao (3 vendor) |
| TViệt giọng trẻ | chưa rõ | chưa rõ (test P0) | Deepgram tune VN tốt hơn |

**Chọn B.** Lý do: cân bằng tốt nhất giữa độ trễ thấp + không-cướp-lời + resilience mạng nhà + trí nhớ — khớp đúng 3 ưu tiên. **C là fallback** nếu Phase 0 cho thấy Gemini Live nghe giọng trẻ VN kém.

## 3. Recommended Solution

### Kiến trúc MVP (Phương án B)

```
Flutter App (iOS+Android)
  • chọn bé (2 profile) • Rive char + lip-sync • PIN khoá khu phụ huynh
  • push-to-talk / auto VAD • timer thời lượng • LiveKit client (voice-only)
        │ WebRTC (token từ backend mint)
  LiveKit Cloud (free Build tier ~900 min/mo, asia-southeast1)
        │ dispatch
  LiveKit Agent (Python) — GCE e2-micro always-on, SG
    • on_start: fetch child profile từ Supabase → inject vào system prompt
    • TurnDetector: min_endpointing_delay ~1.2-1.5s (không cướp lời trẻ chậm)
    • Gemini safety = strict • topic blocklist guardrail
    • lưu full text transcript + summary cuối phiên
        │ native audio speech-to-speech (EN/VN)
  Gemini Live (Vertex AI, Singapore)        Supabase
                                              • 2 profiles • transcripts + summaries
                                              • daily usage counter (server quota)
```

### Quyết định then chốt

- **Trí nhớ = context-stuffing, KHÔNG RAG.** 2 user, profile ~1KB → nhồi thẳng system prompt lúc start. Né bug `update_chat_ctx()` của Gemini Live. Đúng KISS.
- **Token minting:** backend nhỏ (endpoint trong agent service / Supabase Edge Function) cấp LiveKit access token. Client không giữ API key.
- **Time-limit 2 lớp:** client (đếm ngược UX thân thiện) + server (Supabase counter là nguồn chân lý, chặn cấp token mới khi hết quota).
- **Safety 3 lớp:** (1) Gemini safety settings strict, (2) system prompt "bạn của trẻ 5 tuổi, chủ đề an toàn", (3) topic blocklist đơn giản ở agent.
- **Privacy:** chỉ lưu text (không audio); khuyến nghị auto-prune transcript sau ~30 ngày để giữ child data tối thiểu.

### System prompt (định hướng — chi tiết để khi plan)

- Persona: người bạn ấm áp, kiên nhẫn, khích lệ, KHÔNG phán xét; nhớ tên/sở thích/chuyện hôm qua của bé.
- Ngôn ngữ: mặc định theo ngôn ngữ bé thoải mái; chêm/chuyển EN tự nhiên, không ép.
- Câu ngắn, từ đơn giản, nói chậm, dừng giữa câu (cho bé kịp phản hồi).
- Chủ đề an toàn tuổi 5; từ chối nhẹ nhàng + chuyển hướng khi gặp chủ đề ngoài phạm vi.

## 4. Implementation Considerations & Risks

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Gemini Live nghe giọng trẻ VN kém | **Cao** | **Phase 0 spike trước**; fallback phương án C (Deepgram VN) |
| Cướp lời trẻ nói chậm | Cao | LiveKit turn-detector, min_endpointing_delay 1.2-1.5s, STT-mode |
| Chi phí model vượt nếu con mê chơi | TB | Server hard time-limit; theo dõi $; cân nhắc C nếu phút cao |
| Bug update_chat_ctx() Gemini | TB | Inject memory qua system prompt lúc start (đã thiết kế vậy) |
| Mất mạng giữa chừng | TB | LiveKit reconnect + UX báo nhẹ "đợi xíu nhé" |
| Nội dung không phù hợp lọt ra | Cao | 3 lớp safety; phụ huynh giám sát; review log định kỳ |

**⚠️ Phase 0 spike correction (2026-06-21):** The native-audio model
`gemini-live-2.5-flash-native-audio` is served **ONLY in `us-central1`** — NOT
`asia-southeast1` (Singapore) as the brief assumed, NOT `global` (live-probed,
both rejected). This invalidates the "co-locate in Singapore" plan and adds
VN→US latency. Measured first-audio latency VN→us-central1 ≈ **1.25–1.4s**
(idealized, synthetic adult voice) — above the <1.2s target but user accepted to
proceed with B. LiveKit Cloud/agent region choice must account for the model
living in us-central1. See `phase0-smoke-test-findings-gemini-live-vn-latency-report.md`.

**Research evidence (2026):**
- Gemini Live: hỗ trợ Vietnamese + code-switch native; latency first-audio ~320-800ms; VN→SG total ~800ms-1.2s. **Chưa có benchmark giọng trẻ 5 tuổi** → phải tự test.
- LiveKit Agents v1.6+: turn-detector model-based, tunable endpointing; Flutter SDK production-ready; Cloud free Build tier đủ cho 900 min/mo.
- Gemini Live cost ~$0.023/min → ~$41/mo cho 60 min/day (2 bé). Đây là chi phí trội nhất.
- Known bugs: mid-sentence cutoff (#2117) → lý do giữ LiveKit; update_chat_ctx() drop system msg → inject lúc start.

## 5. Success Metrics & Validation

- **Phase 0 go/no-go:** Gemini Live hiểu ≥~85% giọng thật 2 con; không cướp lời rõ rệt; latency cảm nhận tự nhiên; code-switch EN/VN mượt.
- Độ trễ cảm nhận <~1.2s từ lúc bé dứt lời.
- 0 nội dung không phù hợp lọt qua trong test giám sát.
- 2 profile tách bạch trí nhớ, không lẫn.
- Hard time-limit chặn đúng khi hết quota (server-side).
- Chi phí thực tế trong tầm vài chục USD/tháng.

## 6. Phases / Next Steps

- **Phase 0 — Spike (1-2 ngày) ⚠️ BẮT BUỘC TRƯỚC:** test Gemini Live native audio với giọng thật 2 con (hiểu giọng? code-switch? cướp lời? latency VN→SG?). → go/no-go B vs C.
- **Phase 1 — Voice loop lõi:** LiveKit + Agent + Gemini Live, 1 profile hard-code, system prompt song ngữ + safety. Chạy trên 1 máy thật.
- **Phase 2 — 2 profile + trí nhớ:** Supabase schema, fetch/inject memory, lưu transcript + summary, chọn bé.
- **Phase 3 — Nhân vật + time-limit:** Rive char + lip-sync, đếm ngược, server quota, PIN khu phụ huynh.
- **Phase 4 — Hoàn thiện:** xử lý mất mạng nhẹ nhàng, tinh chỉnh turn-detection, polish UX.
- **Post-MVP:** parent transcript dashboard, pronunciation scoring (Azure), songs/games, hình ảnh toán/khoa học, compliance khi go-public.

## 7. Unresolved Questions

1. **Quota/ngày cụ thể:** bao nhiêu phút/bé/ngày là hợp lý cho tuổi 5? (đề xuất bắt đầu 15-20 phút/bé, chỉnh sau).
2. **Gemini model version:** chốt model native-audio cụ thể lúc plan (preview cũ deprecated 2026-03; dùng bản mới nhất ổn định).
3. **Retention transcript:** auto-prune sau bao lâu? (đề xuất 30 ngày) — cần user xác nhận lúc plan.
4. **Rive asset:** tự thiết kế nhân vật hay dùng asset có sẵn? ảnh hưởng timeline Phase 3.
