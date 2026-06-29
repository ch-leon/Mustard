## Live Google Calendar connect (auth + fetch) — BAK-45

Wires the live Google Calendar OAuth + fetch flow on top of the existing tested pure
layer. Real `primary`-calendar meetings now sync into `CalendarEvent` rows (Week + notch).

Closes [BAK-45](https://linear.app/bakinglions/issue/BAK-45).

### What's in it
- **Loopback OAuth** (`LoopbackRedirectServer` + `GoogleAuthSession`) — Desktop-app flow:
  consent in the system browser, code captured on `127.0.0.1:<port>`, PKCE. (Not
  `ASWebAuthenticationSession` — that needs a custom scheme; loopback matches the
  Desktop client type. See spec.)
- **Token client** (`GoogleTokenClient`) — code→token exchange + refresh; refresh
  preserves the existing refresh token.
- **Events client** (`GoogleEventsClient`) — `events.list` for today→+14d, `primary`,
  `singleEvents=true&orderBy=startTime`.
- **Keychain store** (`TokenStore`/`KeychainTokenStore` + `InMemoryTokenStore`) — token
  **and** client id/secret; client secret is user-entered, Keychain-only, never on disk/git.
- **Upsert reconciler** (`CalendarSync.upsertEvents`) — insert/update by `externalId`,
  delete in-window vanished.
- **`GoogleCalendarService`** (`@Observable`, mirrors `AgentService`) — connect /
  disconnect / refreshIfNeeded / fetch + connection state.
- **Settings UI** — Connect / Refresh now / Disconnect in `SourceSettingsView`.
- **App wiring** — constructed in `MustardApp` with real shells; pumped from the 60s loop.

### Design / plan
- Spec: `docs/superpowers/specs/2026-06-28-live-google-calendar-connect-design.md`
- Plan: `docs/superpowers/plans/2026-06-28-live-google-calendar-connect.md`

### Checks
- `swift test` → **314 pass / 1 skip / 0 fail** (19 new Calendar tests)
- `swift build` → clean · `./build-app.sh` → `Mustard.app` built

### Review
Fresh-context review: **approve, no blocking findings** (standards/spec/risk/tests). The
one robustness finding (orphaned auth-timeout continuation) was **fixed in this PR**.
Three minor follow-ups filed as [BAK-71](https://linear.app/bakinglions/issue/BAK-71).

### Risk
**High** (OAuth/auth + Keychain) → routes to the `deep-review` panel before auto-merge.
No irreversible outward action.

### Not covered by unit tests (by design — injected-shell rule)
Real loopback socket, real Keychain, and the live Google consent — these are the manual
live test (Task 10) for Leon: paste the Desktop client id+secret in Settings → Connect →
approve → meetings appear on Week/notch.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
