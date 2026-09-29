# Functional Requirements — Reader (iOS) v1

**Status:** Locked from design-tree decisions (2026-09-17)  
**Product job:** Listen to articles offline.

---

## 1. Purpose

v1 must let a user browse the web in-app, extract a clean article, save it on device, and listen with Apple’s on-device text-to-speech — with no backend.

Browse and Reader Mode exist to feed that pipeline. Saved + Speak are the must-haves.

---

## 2. Personas / primary use

- User finds an article in the in-app browser (URL, Google search, or a domain chip from past saves).
- User saves a clean copy.
- User later opens Saved (app home) and plays audio offline, optionally reading along in the cleaned view.

---

## 3. Information architecture

| Surface | Role |
|--------|------|
| **Saved** | App home / default tab. Offline library. |
| **Browse** | Separate tab. Live web + Reader Mode + Save. |

Browse has its own **start/landing** screen (not the app home): Google-style URL/search bar + domain chips from sites the user has saved before.

---

## 4. Functional requirements

### 4.1 Browse

| ID | Requirement |
|----|-------------|
| B1 | User can open Browse and see a start screen with a Google-style URL/search bar. |
| B2 | If input is a URL, load it in the in-app WebView. |
| B3 | If input is non-URL text, run a Google Search and show results in the WebView. |
| B4 | User can follow links inside the WebView (normal navigation). Opening a page is always a user action. |
| B5 | Start screen shows **domain chips** derived from domains in Saved (sites saved before). Tap chip → open that site in the browser. |
| B8 | Start screen shows **Recently visited**: last N top-level http(s) pages (title, host, **favicon**). Tap row → reopen that URL in Browse. |
| B9 | Recents are automatic, deduped by canonical URL, capped (e.g. 30). Not tabs; multi-tab is out of scope. |
| B10 | Clearing Recents (when exposed) must not delete Saved articles. |
| B11 | While the address bar is focused, show suggestions: **local Recents/Saved matches first**, then **unofficial Google Search suggest** (`suggestqueries.google.com`, debounced). Tap a row → navigate (URL) or Google Search (query). If Google fails/blocks, show locals only (no error banner). Not an official Google API. |
| B6 | No curated site directory, no mass/auto-opening of links. |
| B7 | Browse requires network to load live pages. |

### 4.2 Reader Mode

| ID | Requirement |
|----|-------------|
| R1 | Reader Mode is **manual**: user taps Reader. |
| R2 | Reader shows cleaned article content for the current page when extraction succeeds. |
| R3 | From Reader, user can Save and/or Speak (subject to extraction success and speech rules). |
| R4 | No auto-enter Reader when a page “looks like” an article. |

### 4.3 Save

| ID | Requirement |
|----|-------------|
| S1 | Save is available from **Browse or Reader**. |
| S2 | Save always runs article extraction. |
| S3 | On success, persist a full offline article record (see data fields in Technical Spec). |
| S4 | On extraction failure: **block Save**, show why, **store nothing** (no bookmark-only, no dirty snapshot). |
| S5 | Saved articles remain available without network. |

### 4.4 Saved (Library) — app home

| ID | Requirement |
|----|-------------|
| L1 | Default landing surface of the app is Saved. |
| L2 | List shows title, site, and date for each article. |
| L3 | Tap row → open offline cleaned article (HTML). |
| L4 | Separate **play** control on the row (not tap-row-to-speak). |
| L5 | User can search within saved articles. |
| L6 | User can delete (e.g. swipe to remove). |

### 4.5 Speech (Apple TTS default; optional on-device Kokoro)

| ID | Requirement |
|----|-------------|
| P1 | **Default:** Apple on-device TTS (system voices). **Optional:** Kokoro via FluidAudio on A15+ (the only local engine; Chatterbox Nano was removed 2026-09-24), user-selected; Apple stays the default and the fallback (no model, render failure, or Kokoro crash). An article keeps one voice's audio; switching voice re-renders it, old-voice audio plays until each paragraph is replaced. |
| P2 | Controls: play, pause, stop. |
| P3 | Skip forward / back by **paragraph**. |
| P4 | Speed control approximately 0.75x–2x. |
| P5 | Remember playback position per article and resume later. |
| P6 | Speak works fully offline from saved plain text. |
| P7 | Lock screen / Control Center controls are **out of v1**. |

### 4.6 Offline / network

| ID | Requirement |
|----|-------------|
| O1 | Saved reading + Speak work fully offline. |
| O2 | Browse needs network for live pages. |
| O3 | ~~No requirement to cache recently browsed~~ **Superseded by B8–B10**: keep last-N Recents with favicons; still no multi-tab. |

---

## 5. Non-goals (v1)

- Backend, accounts, or sync
- Share Extension / Safari share-in
- Universal Links / open-in as a primary entry
- Next-page prefetch or auto-advance
- Custom or cloud voices
- Lock screen / Control Center playback
- Folders, tags, highlights
- Cross-platform (Android / Flutter / RN) — iOS native only
- Auto Reader Mode
- Saving failed extractions as bookmarks or raw snapshots

---

## 6. Success criteria

v1 is successful when a user can:

1. Reach an article via Browse (URL, Google search, or domain chip).
2. Save a clean offline copy (or get a clear failure).
3. From Saved, read that copy offline and listen with play/pause/stop, paragraph skip, speed, and resume — with no account and no server.

---

## 7. Future (explicitly deferred)

- Share Extension
- Next-page detection / prefetch / auto-scroll
- Custom voice service
- Lock screen controls
- Sentence-level skip
- Fetch-HTML extraction fallback (if spike shows need)
- Folders / tags / highlights
- Sync / multi-device

---

## 8. Decision log (summary)

| Topic | Decision |
|-------|----------|
| Product job | Offline listening (Save + Apple TTS) |
| App home | Saved |
| Browse start | URL/Google bar + domain chips from saves |
| Entry | In-app WebView only; no spam-open |
| Reader | Manual |
| Save | Browse or Reader; always extract; fail = store nothing |
| Speech skip | Paragraph |
| Extraction | Live-DOM Readability default; spike required; swappable |
