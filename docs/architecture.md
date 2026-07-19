# Mustard — Architecture

Deep reference for how Mustard is put together. For the quick orientation see
[`CLAUDE.md`](../CLAUDE.md); for decisions and their rationale see [`adr/`](adr/).

## 1. Shape

- **Native SwiftUI**, macOS 14+, Swift 6 toolchain.
- **Swift Package** (not an `.xcodeproj` yet — ADR-0002):
  - `MustardKit` (library): all models, logic, agent, calendar, views.
  - `Mustard` (executable): `@main` app, window/scene, floating panel + notch
    controllers, the scheduled-sweep loop.
  - `MustardTests`: XCTest target.
- **SwiftData** for persistence; **CloudKit-shaped schema** so iCloud sync is a
  later capability flip, not a migration (ADR-0001).
- The **agent** is a single worker bound to this Mac, shelling out to the `claude`
  CLI under Leon's subscription (ADR-0003).

## 2. Layered modules

```
Views  ──────────────▶ depend on Logic + Agent + Models
Agent  ──────────────▶ depend on Logic + Models   (AgentService, ClaudeRunner, VaultSweep)
Calendar ────────────▶ depend on Models           (GoogleOAuth, GoogleCalendarParser)
Logic  ──────────────▶ depend on Models only      (pure, fully unit-tested)
Models ──────────────▶ SwiftData @Model + enums
```

The dependency arrow only points down. **All branching logic lives in `Logic/` or
in pure parsers**, so it is testable without SwiftUI or a network. Views are thin.

## 3. Data model (SwiftData)

CloudKit rules observed everywhere: every relationship optional, every stored
property has a default or is optional, **no `@Attribute(.unique)`**.

| Model | Purpose | Notable fields |
|-------|---------|----------------|
| `Area` | top-level grouping | name, colorHex, → lists |
| `TaskList` | list within an area | name, → area, → tasks |
| `MustardTask` | a task (mine or agent's) | `uid` (drag id), title, notes, `statusRaw`/`ownerRaw` (typed accessors), `scheduledAt`, `estimateMinutes`, `completedAt` |
| `Recommendation` | an agent proposal (pre-execution) | title, body, `proposedActionType`, `confidence`, `reasoning`, `draft`, `source`/`sourceContext`/`sourceURL`, `comment`, `snoozedUntil`, `decisionRaw`, `executionStateRaw`, → outputs |
| `OutputCard` | legacy recommendation-execution output (pre-ADR-0010) | content, kind, `reviewRaw`, → recommendation |
| `AgentRun` | one delegated-task conversation | `provider`, `state`, `providerSessionID`, `requiresConnectedWorker`, `nextAttemptAt`, `autoRetryCount`, → task, → messages |
| `AgentMessage` | one ordered turn in a run | `sequence`, `role`, `kind`, `content`, `links`, → run |
| `AgentDraft` | a file-backed draft the agent produced | `kind`, `title`, `relativePath` (under `_agent/drafts/`), → run. Body lives in the vault file, not the store |
| `CalendarEvent` | a Google Calendar meeting | externalId, calendarId, title, start, end, isAllDay, joinURL, location |

> **F24 note:** delegated agent tasks now carry an `AgentRun`/`AgentMessage` conversation and
> land in the board's **Needs Review** column (ADR-0010). `OutputCard` remains only for the
> legacy recommendation-execution path; delegated work does not create one.

Enums are stored as `…Raw` strings with computed typed accessors — primitives
persist cleanly in SwiftData/CloudKit while call sites stay type-safe.

## 4. The agent loop

```
schedule (SweepScheduler) ─┐
manual "Sweep" ────────────┴▶ AgentService.sweep(vaultPath)
                                 │  claude -p (VaultSweep.prompt) in vault cwd
                                 ▼
                            parse → insert Recommendations (pending)
                                 │
                    applyTrust(level)  ── confidence × trust × !gated ──▶ auto-approve
                                 │
        user triage in AgentConsole / Notch ──▶ decide(.approved)
                                 ▼
                    execute(rec): claude -p (VaultSweep.executePrompt) in vault cwd
                                 ▼
                    OutputCard (summary|error)  ── auto-accept if Trusted+confident
                                 ▼
                    Review queue: Accept · Revise (re-execute) · Discard
```

- `ClaudeRunner.run: ClaudeRun` spawns `Process`: scrubbed env (drops
  `ANTHROPIC_*`/`CLAUDE*`), stdin = `/dev/null`, parses `{result, is_error}` JSON,
  flags rate-limits. Overridable via `MUSTARD_CLAUDE_BIN` for tests.
- `AgentService` is `@MainActor @Observable`, serial (`isExecuting` guard) — one
  `claude` at a time, subscription-friendly.
- `TrustPolicy` (pure): `shouldAutoApprove/​Accept(actionType:trust:confidence:)`,
  `isGated`, `autoConfidenceThreshold = 0.7`.

## 5. Surfaces

| Surface | File | Behaviour |
|---------|------|-----------|
| Main window | `RootView` | calm sidebar → Today · Board · Week · Agent; ⌘K command bar overlay |
| Today | `TodayView` + `TimelineRow` | scheduled timeline, capture, complete, carry-forward, tap → detail |
| Board | `BoardView` | Kanban by status, drag-drop, per-column add, tap → detail |
| Week | `WeekView` | Mon–Sun grid + unscheduled rail, drag to (un)schedule, meetings interleaved |
| Agent | `AgentConsoleView` | source picker, Sweep, Auto-interval, Trust menu, rich Recommendation drawer, Review queue |
| Notch | `NotchSurface` | borderless status-bar `NSPanel` at the physical notch; idle rotates focus→next-meeting→waiting; hover expands to meetings + recs + capture |
| Hover | `HoverPanel` | non-activating floating `NSPanel`; current focus + next-up tasks + waiting badge |
| Task detail | `TaskDetailSheet` | edit title/notes/status/owner/estimate/schedule, mark done, delete |

`NotchController` and `HoverPanel` own `NSPanel`s configured non-activating
(`.nonactivatingPanel`) so they never steal focus; `.canJoinAllSpaces`,
floating/status-bar level.

## 6. Calendar (data layer done; live fetch pending)

- `GoogleOAuth`: PKCE (`verifier`/`challenge`, RFC 7636), `authorizationURL`,
  `parseTokenResponse` — all pure/tested. Flow = OAuth 2.0 desktop client + PKCE +
  loopback redirect.
- `GoogleCalendarParser.parseEvents`: Google `events.list` JSON → `[ParsedEvent]`,
  handling timed vs all-day, Meet links, cancelled-event skipping — pure/tested.
- **Not yet built:** the live `GoogleAuthSession` (loopback + `ASWebAuthenticationSession`)
  and `GoogleCalendarService` (connect/refresh/fetch → upsert `CalendarEvent`) +
  Settings UI. Blocked on Leon's OAuth client id. Meetings already render on the
  Week grid and notch from `CalendarEvent` rows.

## 7. Known constraints

- Agent is Mac-anchored (subscription auth on the logged-in CLI).
- Native app can't be screenshotted from the dev session (no TCC) — UI verified by
  build + Leon's eyes.
- CloudKit + iOS require migrating SPM → Xcode project for entitlements (ADR-0004).
