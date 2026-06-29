# Deep-Review Panel — BAK-45 (high-risk: OAuth/auth + Keychain)

Three independent fresh-context reviewers, each instructed to default to BLOCK.

## Round 1 — HELD (3/3 block)

| Lens | Verdict | Blocking finding |
|------|---------|------------------|
| Correctness | block | Non-2xx events response → `parseEvents` returns `[]` → upsert deletes all in-window events (silent data loss); state stays `connected`. `HTTPTransport` discarded the status code. |
| Security | block | `NWListener(on: .any)` bound `0.0.0.0` (RFC 8252 §8.3 wants loopback-only); no `state` param / anti-forgery check → auth-code injection / login-CSRF. |
| Spec | block | `refreshIfNeeded` tested only the expired case (spec requires expired/near-expiry/valid); `CalendarWindow.rolling` had no pinned-UTC test (CLAUDE.md). |

## Fixes applied in-run (commit 966be73)

- `HTTPTransport` → `(Data, Int)`; `GoogleEventsClient.fetch` throws on non-2xx
  (401→`invalidGrant`, else→`server`); `GoogleTokenClient` classifies non-2xx via
  `error(from:status:)`, preserving HTTP-400 `invalid_grant` detection.
- `LoopbackRedirectServer.start()` binds `127.0.0.1` via
  `NWParameters.requiredLocalEndpoint`.
- `GoogleOAuth.authorizationURL` gains `state`; `GoogleAuthSession.connect` generates a
  random state and rejects the redirect on mismatch before any exchange/persist.
- Tests added: `refreshIfNeeded` near-expiry + valid; `CalendarWindow.rolling` pinned-UTC;
  events 401/503; token non-2xx; state-mismatch rejection; fetch-error-keeps-events.

## Round 2 — PASS (3/3 clear)

| Lens | Verdict | Note |
|------|---------|------|
| Correctness | clear | Non-2xx can no longer reach `parseEvents`; `fetch` keeps rows on generic error, clears token on invalidGrant; invalid_grant still detected. No new regressions. |
| Security | clear | Loopback-only bind + `state` round-trip verified; secret/tokens Keychain-only; PKCE S256; readonly; no irreversible action; no real secrets committed. |
| Spec | clear | All three refresh cases + UTC window test present; full acceptance set met; hardening is in-scope, not creep. |

**Checks:** `swift test` → 323 pass / 1 skip / 0 fail; `swift build` clean.

## Non-blocking follow-ups noted by the panel (track separately)
- `events.list` has no pagination (`maxResults=250`); >250 in-window events would over-delete. Unlikely for one personal calendar.
- `LoopbackRedirectServer.handle` reads one `conn.receive`; a split request line could resolve to `.missingCode` (user retries). Live-path robustness.
- `GoogleToken.isExpired` uses ambient `Date.now` but is unused by the refresh path; consider removing.
- `KeychainTokenStore` uses default accessibility; revisit for any future multi-device/CloudKit story.

## Verdict
Panel passes. merge-policy may merge with `--deep-review passed`.
