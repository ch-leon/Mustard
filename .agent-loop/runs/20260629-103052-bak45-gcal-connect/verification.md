# Verification — BAK-45

## Required checks (.agent-loop/checks.yml)

| Check | Command | Result |
|-------|---------|--------|
| test | `swift test` | **PASS** — 314 executed, 1 skipped, 0 failures |
| build | `swift build` | **PASS** — Build complete (clean; one pre-existing `note:` re OutputCard Sendable) |
| app bundle | `./build-app.sh` | **PASS** — `build/Mustard.app` produced + signed |

## New tests added (19)

- `LoopbackRedirectServerTests` (4) — redirect query → code / denied / server-error / missing-code.
- `GoogleTokenClientTests` (4) — exchange body fields; exchange parse; refresh preserves refresh token; invalid_grant throws.
- `GoogleEventsClientTests` (2) — events URL window+ordering; fetch parses events.
- `TokenStoreTests` (2) — in-memory round-trip; clearToken keeps credentials.
- `CalendarSyncTests` (3) — insert new; update by externalId; delete vanished in-window.
- `GoogleAuthSessionTests` (1) — connect exchanges + persists token/credentials; opens correct consent URL.
- `GoogleCalendarServiceTests` (3) — connect→fetch upserts; refreshIfNeeded refreshes expired (preserving refresh token); disconnect clears token + purges events.

## Out of unit scope (covered by build + the manual live test, Task 10)

- Real `NWListener` loopback socket + the close-tab response.
- Real macOS Keychain read/write (`KeychainTokenStore`).
- The actual Google consent screen and end-to-end token exchange.

These follow the repo's "shells are injected; pure logic is tested" rule (same as
`ClaudeRunner`).

## Manual live test (Task 10 — Leon)

1. `open build/Mustard.app` → Settings → Google Calendar → paste Desktop client id + secret → Connect.
2. Approve in browser → "you can close this tab" → Settings shows Connected + last-synced.
3. Real primary-calendar meetings (today → +14d) appear on Week + notch; Refresh re-syncs; a cancelled event disappears.
4. Disconnect removes synced meetings; credentials stay prefilled for one-tap reconnect.
