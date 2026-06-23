# Monami — Privacy Policy

_Last updated: 2026-06-23_

Monami is a friendly bilingual (Vietnamese/English) voice companion for young
children. This policy explains what data the app handles and how. It is written
plainly for parents.

## Who we are

Monami is a small, independent project. Contact: **phucnt0@gmail.com**.

There are **no user accounts**. The app identifies a device by a random,
anonymous identifier generated on the device — it is **not** linked to your name,
email, phone number, or any real-world identity.

## What data we handle

**Child profile (you create it):**
- Child's first name (as you type it), gender, age, and interests.
- This is stored on our backend (Google Cloud Firestore, United States), keyed to
  the device's anonymous identifier.

**Conversation memory:**
- After a chat, a short text summary of what the companion learned (e.g. "likes
  dinosaurs") is stored, so it can greet the child warmly next time.
- You can **view, edit, or delete** this memory at any time in the app, and you
  can **delete a child** entirely (which deletes their profile and memory).

**Child's voice (audio):**
- While the child talks, audio is streamed in real time to **Google Vertex AI
  (Gemini)** to understand speech and reply. This is required for the app to work.
- **Audio is not stored** by us or on the device — it is processed live and
  discarded. Only the short text summary above is kept.
- Google processes this audio as our AI provider; see Google Cloud's terms.

**Guest mode:**
- If you use "Khách (chơi nhanh)" / Guest, **nothing is stored** — no profile, no
  memory. The session is forgotten when you leave.

## What we do NOT do

- We do **not** sell or rent your data.
- We do **not** use third-party advertising or analytics SDKs.
- We do **not** ask for or collect contact info, location, photos, or contacts.
- We do **not** create accounts or track you across other apps.

## Children's privacy

Monami is designed for young children and is intended to be set up and supervised
by a parent or guardian. The only personal data is what a parent chooses to enter
(name, gender, age, interests) plus the conversation summaries described above,
all tied to an anonymous device identifier. A parent can review and delete this
data in the app at any time. For questions or deletion requests, email
**phucnt0@gmail.com**.

## Data retention & deletion

- Profiles and memory are kept until **you delete them** in the app (delete a
  child, or clear a child's memory).
- Deleting the app does not by itself delete server-side data, but you can request
  full deletion by emailing **phucnt0@gmail.com** with no need to identify
  yourself beyond the request.

## Where data is processed

- Backend + storage: Google Cloud (Firestore, Cloud Run) in the United States.
- AI speech/voice: Google Vertex AI (Gemini) in the United States.

## Changes

We may update this policy; the "Last updated" date above will change. Material
changes will be noted in the app's release notes.

## Contact

**phucnt0@gmail.com**
