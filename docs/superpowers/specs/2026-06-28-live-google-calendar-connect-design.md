# Live Google Calendar Connect (auth + fetch) — Design

**Issue:** [BAK-45](https://linear.app/bakinglions/issue/BAK-45) · **Project:** Mustard · **Priority:** High
**Date:** 2026-06-28 · **Branch:** `leon/bak-45-live-google-calendar-connect-auth-fetch`

## Goal

Wire the *live* Google Calendar flow on top of the existing, tested data layer so real
meetings sync into `CalendarEvent` rows and render on Week + notch. Today the pure
pieces exist (`GoogleOAuth`, `GoogleCalendarParser`) but nothing performs the OAuth
handshake, talks to the network, stores tokens, or exposes a connect UI.

## Context — what already exists

- `GoogleOAuth` (pure): PKCE pair, `authorizationURL(clientId:redirectURI:pkce:)`,
  `parseTokenResponse(_:now:) -> GoogleToken?`. Unit-tested. Scope is
  `calendar.readonly`.
- `GoogleCalendarParser` (pure): `events.list` JSON → `[ParsedEvent]`, drops
  `cancelled`, handles timed + all-day. Unit-tested.
- `CalendarEvent` `@Model`: upsert keyed on `externalId`; `calendarId` defaults
  `"primary"`. CloudKit-shaped (no `.unique`).
- `SourceSettingsView`: existing Settings surface to extend.
- `MustardApp`: owns services and runs a 60s scheduled loop.

## Decisions (locked during brainstorming)

- **Credentials:** OAuth client is **Desktop** type (Leon already has id + secret).
  Entered once in the Settings panel, stored in **Keychain** alongside tokens —
  nothing in git, survives rebuilds, works for a double-clicked `.app`.
- **Auth flow:** **loopback HTTP listener** (Google's documented Desktop-app flow),
  *not* `ASWebAuthenticationSession`. The issue text said "loopback +
  ASWebAuthenticationSession," but those don't combine: `ASWebAuthenticationSession`
  dispatches on a custom URL *scheme*, while a Desktop client redirects to
  `http://127.0.0.1:<port>` (no scheme). Loopback matches the credentials Leon has.
- **Window:** start of today → +14 days, rolling.
- **Calendars:** `primary` only (multi-calendar is YAGNI).
- **Disconnect:** clear tokens from Keychain, **keep** client id/secret (one-tap
  reconnect), purge synced `CalendarEvent` rows.
- **Reconcile deletions:** upsert deletes in-window events no longer returned.

## Components

All new code in `Sources/MustardKit/Calendar/`. Repo rule: pure logic is unit-tested;
network / Keychain / browser are thin injected shells.

| Unit | Responsibility | Testable seam |
|------|----------------|---------------|
| `LoopbackRedirectServer` | Bind `NWListener` on `127.0.0.1:<random port>`, hand back the `redirect_uri`, await the inbound GET, reply "you can close this tab," cancel. | Pure `parseRedirect(query:)` → `code` / `error`; only the socket is the shell. |
| `GoogleTokenClient` | HTTP for code→token exchange + refresh. | Pure form-body builders; injected transport closure; reuses `GoogleOAuth.parseTokenResponse`. |
| `GoogleEventsClient` | HTTP GET `events.list` for a time window. | Pure URL/query builder; injected transport; reuses `GoogleCalendarParser`. |
| `TokenStore` (protocol) + `KeychainTokenStore` + `InMemoryTokenStore` | Persist `GoogleToken` (refresh token) **and** client id/secret. | Protocol → in-memory impl for tests; real Keychain via build + live use. |
| `GoogleAuthSession` | Orchestrate connect: PKCE → start server → open browser → await code → exchange → persist. | Injected pieces (browser-opener closure, server, token client, store). |
| `GoogleCalendarService` (`@Observable`) | Public API: `connect()`, `disconnect()`, `refreshIfNeeded()`, `fetch(window:)`; holds connection state. Mirrors `AgentService`. | All the above injected + a `ModelContext`. |
| `upsert(parsed:into:calendarId:)` | Pure-ish reconciler: match by `externalId`, insert/update, delete in-window vanished. | In-memory `ModelContainer`. |

Settings UI extends `SourceSettingsView` with a Google Calendar section. `MustardApp`
owns the service and calls `refreshIfNeeded()` + `fetch()` from the existing 60s loop.

## Data flow

**Connect**
1. User pastes client id + secret in Settings, taps **Connect**.
2. `GoogleAuthSession`: PKCE → `LoopbackRedirectServer` binds a random port yielding
   `redirect_uri=http://127.0.0.1:<port>` → consent URL via
   `GoogleOAuth.authorizationURL` → open in system browser (`NSWorkspace.shared.open`).
3. User consents → Google redirects to loopback → server captures `code`, replies with
   a close-tab page, cancels.
4. `GoogleTokenClient.exchange(code:)` → `GoogleToken` (incl. refresh token) → Keychain.
   State → `connected`.

**Fetch / refresh** (on connect, on manual **Refresh now**, and from the 60s loop)
- `refreshIfNeeded()`: if `token.isExpired` (or within 60s skew), `refresh()` using the
  stored refresh token; persist.
- `fetch()`: `GoogleEventsClient` GETs `events.list` with
  `singleEvents=true&orderBy=startTime&timeMin&timeMax` → `GoogleCalendarParser` →
  `upsert(...)` into the `ModelContext`.

## Error handling

All surfaced via `GoogleCalendarService.state`
(`.disconnected / .connecting / .connected / .failed(reason)`), shown in Settings;
nothing crashes.

- User denies / closes browser → listener times out (~120s) → `.failed`.
- Port bind fails → retry a new port once, else `.failed`.
- `invalid_grant` on refresh → drop to `.disconnected`, prompt reconnect.
- Fetch network error → keep last-synced rows, show error, no purge.

## Testing (TDD; pinned UTC clock + ISO fixtures per repo rules)

- **Pure:** `parseRedirect(query:)`; token-request body builders (exchange + refresh);
  events-list URL builder.
- **Logic:** `refreshIfNeeded` decision (expired / near-expiry / valid) with injected
  `now`.
- **Data:** `upsert` — insert new, update by `externalId`, delete vanished — in-memory
  `ModelContainer`.
- **Store:** `TokenStore` round-trip via `InMemoryTokenStore`.
- **Service:** `GoogleCalendarService.connect()` happy path with all shells stubbed →
  token persisted, state `connected`.
- **Out of unit scope** (build + Leon's live test): real Keychain, real `NWListener`
  socket, the actual Google consent screen.

## Out of scope (YAGNI)

Multi-calendar selection; write access (scope stays `calendar.readonly`); push/webhook
sync (poll only); recurring-event expansion beyond `singleEvents=true`; non-Google
providers.

## Risk

Touches `auth`/OAuth (high-risk path in `.agent-loop/risk.yml`) → routes to the
`deep-review` panel before auto-merge. No irreversible outward action: the client
secret is user-entered and Keychain-stored, never committed.
