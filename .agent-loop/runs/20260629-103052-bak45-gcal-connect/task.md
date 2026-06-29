# Run: BAK-45 — Live Google Calendar connect (auth + fetch)

- **Run id:** 20260629-103052-bak45-gcal-connect
- **Issue:** [BAK-45](https://linear.app/bakinglions/issue/BAK-45) (High)
- **Branch:** `leon/bak-45-live-google-calendar-connect-auth-fetch`
- **Spec:** docs/superpowers/specs/2026-06-28-live-google-calendar-connect-design.md
- **Plan:** docs/superpowers/plans/2026-06-28-live-google-calendar-connect.md

## Acceptance criteria (from spec)
- Loopback OAuth connect using the Desktop client (id+secret entered in Settings, Keychain-stored).
- Token exchange + refresh over HTTP; refresh preserves the existing refresh token.
- Fetch `primary` calendar events (today → +14d), upsert into `CalendarEvent`, delete vanished.
- `@Observable` `GoogleCalendarService` with connect/disconnect/refreshIfNeeded/fetch + state.
- Settings "Connect" UI; wired into MustardApp + the 60s loop.
- Pure logic unit-tested; network/Keychain/browser are injected shells.

## Required checks (.agent-loop/checks.yml)
- `swift test`
- `swift build`

## Plan tasks
1. Shared types + redirect parsing
2. GoogleTokenClient (exchange + refresh)
3. GoogleEventsClient (events.list fetch)
4. TokenStore (in-memory + Keychain)
5. Event upsert reconciler
6. GoogleAuthSession (connect orchestration)
7. GoogleCalendarService (@Observable)
8. Settings UI
9. Wire into MustardApp
10. Live verification (manual — Leon)
