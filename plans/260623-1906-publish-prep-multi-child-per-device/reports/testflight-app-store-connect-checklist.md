# TestFlight + App Store Connect checklist (user-side steps)

Everything in code/config is done (name=Monami, square icon, version 1.0.0+2,
privacy policy doc, RELEASE.md, deny-all Firestore rules file). These are the
**Apple-side** steps only you can do (account access). Order matters.

## 0. Prereqs (confirm)
- [ ] Logged in to https://appstoreconnect.apple.com with team `75EN938B6L`.
- [ ] Latest **Program License Agreement agreed** (developer.apple.com/account —
      a stale one blocks signing; you already hit + agreed this once).
- [ ] Host the privacy policy and get a public URL:
      take `docs/privacy-policy.md`, push to a GitHub repo + enable **GitHub
      Pages** (or paste into a public **gist**), note the URL. Needed in step 2.

## 1. Create the app record
- [ ] App Store Connect → **Apps → +** → **New App**.
- [ ] Platform iOS · Name **Monami** · Primary language **Vietnamese** (or English)
      · Bundle ID **com.monami.monamiApp** · SKU `monami-app` · Full access.

## 2. App information / privacy
- [ ] **Age rating: 4+** (answer the questionnaire "None" to all mature content).
      Do **NOT** enable **Kids Category** (it forbids the third-party data sharing
      that Vertex AI needs).
- [ ] **Privacy Policy URL** → paste the URL from step 0.
- [ ] **App Privacy → Data Collection** (be accurate — this is what review checks):
  - **Audio Data** → Collected: **Yes** · Used for: **App Functionality** ·
    Linked to identity: **No** · Tracking: **No** · **Shared with third parties:
    Yes (Google / Vertex AI)**. (Audio is streamed to Google live; **not stored**.)
  - **Name** (child's first name) → Collected: Yes · App Functionality · Linked:
    No (tied to an anonymous device id, not a real account) · Tracking: No.
  - **Other User Content** (gender, age, interests, chat summaries) → Collected:
    Yes · App Functionality · Linked: No · Tracking: No.
  - Nothing else (no location, contacts, photos, identifiers-for-ads, analytics).

## 3. Build the IPA + upload
- [ ] Follow `app/RELEASE.md` → "Build a signed release archive" + "Upload to
      TestFlight" (it fetches the token from Secret Manager; nothing secret typed).
- [ ] Make sure the backend is the **current** Cloud Run revision (RELEASE.md has
      the deploy command) so testers hit the multi-child REST API.

## 4. TestFlight — internal testers only
- [ ] App Store Connect → your app → **TestFlight**.
- [ ] Wait for the build to finish processing (a few minutes).
- [ ] Add **Internal Testers** (people on your team / App Store Connect Users with
      the Tester role). **Do NOT create an External group** — that triggers Beta
      App Review + a privacy pass and isn't needed for ~5 family testers.
- [ ] **What to Test** note (testers see this), e.g.:
      _"Lần đầu mở mỗi phiên nói chuyện có thể chờ vài giây (server đang thức dậy)
      — bình thường. Thêm bé (chọn nam/nữ), nói tiếng Việt, thử chế độ Khách.
      Cho mượn micro khi được hỏi."_
- [ ] **App Review / internal notes** (not user-facing): _"Anonymous, no account.
      Backend gated by a shared token. Child voice is processed live by Google
      Vertex AI and not stored; only short text summaries are kept. Age 4+, not
      Kids Category. US backend (Google Cloud)."_

## 5. Install + smoke test
- [ ] Install **TestFlight** app on a tester device → accept the invite → install
      Monami → run the full flow against Cloud Run (add a girl + boy, talk, memory,
      guest). Expect a few-second cold start on the first session.

## Notes
- Cold start (scale-to-zero) is fine for a small cohort. If testers complain, set
  Cloud Run `--min-instances=1` (small monthly cost) — see RELEASE.md.
- COPPA: app is for children, US backend, **internal** test only; the privacy
  policy + 4+ rating + honest labels cover the disclosure. Revisit before any
  public App Store release.
