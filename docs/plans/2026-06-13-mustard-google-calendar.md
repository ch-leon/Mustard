# Mustard — Google Calendar (Plan 5 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Spec feature 5 / §9. Show real Google Calendar meetings alongside tasks
on the Week grid and a Day view. Read-only first; two-way write later.

**Auth:** OAuth 2.0 for **Desktop app** clients with **PKCE** + loopback redirect
(`http://127.0.0.1:<port>`). No client secret baked in. Tokens stored in Keychain.

**Layering (so most of it is testable without network):**
- PURE + TDD: `PKCE` (verifier/challenge), `GoogleOAuth.authorizationURL(...)`,
  `GoogleOAuth.parseTokenResponse(...)`, `GoogleCalendarParser.parseEvents(...)`.
- IMPURE shell (built once client ID exists, verified live by Leon):
  `GoogleAuthSession` (ASWebAuthenticationSession + loopback), `GoogleCalendarService`
  (connect/refresh/fetch → upsert `CalendarEvent`), Keychain token store.
- MODEL: `CalendarEvent` (externalId, title, start, end, calendarId, joinURL, isAllDay).
- UI: events render on the Week grid per day; a Day view; a Settings sheet to paste
  the client ID and Connect.

**Tasks:**
1. (this turn) `CalendarEvent` model + container wiring + model test. Commit.
2. (this turn) `PKCE` + `GoogleOAuth` (auth URL + token parse) + tests. Commit.
3. (this turn) `GoogleCalendarParser.parseEvents` (dateTime + all-day) + tests. Commit.
4. (this turn) Render `CalendarEvent`s on the Week grid (meeting blocks behind task
   blocks); seed sample events in PreviewData for visual check. Commit.
5. (next turn, needs client ID) `GoogleAuthSession` loopback + `GoogleCalendarService`
   + Keychain + Settings UI; Leon verifies the live consent + fetch.

**Leon's one-time setup (do while I build 1–4):**
1. console.cloud.google.com → create/select a project.
2. APIs & Services → Enable **Google Calendar API**.
3. OAuth consent screen → External → add yourself as a test user.
4. Credentials → Create credentials → OAuth client ID → **Desktop app** → copy the
   **Client ID** (and client secret; for desktop it's non-confidential).
5. Paste the Client ID into Mustard → Settings → Connect (built in task 5).

**Done when:** tasks 1–4 green and meetings (seeded) render on the Week grid; task 5
lights up real meetings after Leon connects.
