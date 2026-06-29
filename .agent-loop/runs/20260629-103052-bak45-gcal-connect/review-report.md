# Fresh-context Review — BAK-45

Reviewer: independent fresh-context agent (zero prior context). Diff:
`d958330...HEAD` on `leon/bak-45-live-google-calendar-connect-auth-fetch`.

## Standards Review
- Blocking: none.
- Architecture boundaries followed exactly: pure seams (`parseRedirect`, body builders,
  `eventsURL`, `CalendarWindow.rolling`, `upsertEvents`) unit-tested; network/Keychain/
  browser/socket are injected shells. `GoogleCalendarService` mirrors `AgentService`.
  Views use `Theme` tokens. No shallow modules, no unrelated refactors.

## Spec Review
- Blocking: none. Every acceptance criterion implemented: loopback auth, token
  exchange + refresh (refresh preserves the existing refresh token — verified + tested),
  events fetch (today→+14d, primary, singleEvents+orderBy), Keychain token+credentials,
  upsert with deletion-reconcile, `@Observable` service + state, Settings Connect UI,
  60s-loop wiring, `calendar.readonly`. Disconnect keeps creds + purges events. No scope creep.

## Risk Review
- Highest risk: **high** (OAuth/auth + Keychain).
- Needs deep-review panel: **yes**.
- Outward actions: **none**. Client secret is user-entered, Keychain-only, never on disk/git.

## Test Review
- `swift test` → 314 pass / 1 skip; `swift build` clean; `./build-app.sh` produces the app.
- 19 new tests cover observable behavior via public interfaces; dates use injected `now`.
- Out of unit scope (build + live test): real socket, real Keychain, real consent.

## Findings actioned
- **Blocking:** none.
- **Fixed in this run** (review item 1+2): leaked/raced `awaitCode` continuation —
  now a single lock-guarded `resolve()` resolves it exactly once on redirect/timeout/stop.
- **Filed as follow-up [BAK-71]:** Theme error token; test stub dedup; window-edge
  inclusivity documentation.

## Verdict
Approve. Proceed to merge-policy (high-risk → deep-review panel before auto-merge).
