# Mustard — Agent Guide (CLAUDE.md)

Mustard is a native macOS command centre that plans **your day and your AI agents'
day together** — a hybrid of Blitz (always-on hover), boring-notch (ambient notch),
Sunsama/Akiflow (day/week planner), and Todoist/Things 3 (calm task management),
with a first-class surface for the work AI agents do for you.

This file orients an agent (or a new engineer) with zero prior context. Read it
before touching code.

## What it is / who it's for

A **personal, local-first** tool for one power user (Leon) who actively delegates
work to AI agents. Not multi-user — but the data layer is shaped so it *could*
generalise later (see ADR-0001). The wedge: every planner assumes *you* are the
only worker; Mustard plans your work and your agents' work on one surface, with a
triage → recommendation → approval → execution → review loop.

## Architecture (one paragraph)

Native **SwiftUI**, **SwiftData** persistence (CloudKit-shaped for later sync).
Code lives in a Swift Package: a **`MustardKit` library** (models, pure logic,
agent layer, views) plus a thin **`Mustard` executable** (`@main` app + window/
panel wiring). The single agent runs **on this Mac only**, shelling out to the
**`claude` CLI in headless `-p` mode** using Leon's Claude **subscription** (no API
key, no metered billing — see ADR-0003). The agent reads/writes an Obsidian vault;
structured app data (tasks, recommendations, outputs, events) lives in SwiftData.

```
┌─ macOS ─────────────────────────────────────────────┐
│  Mustard.app (SwiftUI)                                │
│   Today · Board · Week · Agent   + Notch + Hover + ⌘K │
│        │ @Query / @Bindable                           │
│        ▼                                              │
│  SwiftData (mustard.store)  ◀── AgentService ──▶ claude -p (subscription)
│   tasks · recommendations · outputs · events          │      in vault cwd
└───────────────────────────────────────────────────────┘
```

## Folder layout

```
Mustard/
  Package.swift                  SPM manifest (macOS 14+; MustardKit + Mustard + MustardTests)
  build-app.sh                   assembles a signed build/Mustard.app from the SPM binary
  CLAUDE.md                      this file
  README.md                      human-facing quickstart
  docs/
    architecture.md              the deep architecture reference
    build-order.md               the backlog / build sequence (tracker-as-markdown)
    adr/                         Architecture Decision Records (0001…)
  Sources/
    Mustard/                     executable: MustardApp.swift (@main, windows, panels, scheduler loop)
    MustardKit/
      Models/                    @Model types: Area, TaskList, MustardTask, Recommendation,
                                   OutputCard, CalendarEvent, Enums
      Logic/                     PURE, unit-tested: DayPlanner, WeekPlanner, PersonalBoard,
                                   NotchTicker, SweepScheduler, CommandBarEngine, TrustPolicy,
                                   RecommendationAction, Theme (design tokens)
      Agent/                     ClaudeRunner (Process shell), VaultSweep (prompt+parser),
                                   AgentService (@Observable orchestrator)
      Calendar/                  GoogleOAuth (PKCE/URL/token), GoogleCalendarParser
      Views/                     SwiftUI screens + surfaces (Root, Today, Board, Week,
                                   AgentConsole, Notch, Hover, CommandBar, TaskDetail, rows)
      MustardContainer.swift     builds the on-disk ModelContainer
      PreviewData.swift          in-memory sample container for #Preview
  Tests/MustardTests/            XCTest — one file per Logic/Agent/Calendar unit
```

**Separation rule:** anything with a decision in it (sorting, bucketing, gating,
parsing, scheduling) goes in `Logic/` or as a pure function in `Agent`/`Calendar`
so it can be unit-tested. `Views/` only renders and dispatches. This is why the
suite can cover 73 cases without UI tests.

## Design language — "Things 3 calm" (do not deviate)

All palette/type tokens live in `Logic/Theme.swift` (`Theme.Palette`, `Theme.Fonts`).
Use them — never hardcode colors in views. The look: warm off-white `#FBFAF7`,
hairline dividers, generous spacing, large readable type, **single blue accent**
`#2D7FF9`, agent purple `#7F77DD`, done green `#1D9E75`. Density comes from
hierarchy, not cramming. **One exception:** the notch surface (`NotchSurface.swift`)
is intentionally **dark** — it extends the physical hardware notch — so it uses
explicit dark hex, not `Theme`.

## Testing rules

- **Logic is TDD.** New behaviour in `Logic/`, `Agent` parsers, or `Calendar`
  parsers: write the failing XCTest first, then implement. One test file per unit.
- **Pin time and timezone.** Date logic tests use a fixed `Calendar` with
  `TimeZone(identifier: "UTC")` and ISO fixtures — never the ambient clock/zone
  (AEST shifts day boundaries and flakes otherwise). Inject `now:`/`reference:`.
- **Network/process is injected.** `AgentService` takes a `ClaudeRun` closure;
  tests pass a stub. `ClaudeRunner.run` (the real `Process`) is covered against a
  stub binary via the `MUSTARD_CLAUDE_BIN` env override.
- **Views are verified by build + eye**, not unit tests. `swift build` must pass;
  Leon visually confirms (the in-session shell has no Screen Recording/TCC, so the
  agent cannot screenshot the native app — never claim a view "looks right",
  state it builds and runs and ask Leon to confirm).
- Run: `swift test` (whole suite) or `swift test --filter <SuiteName>`.

## Build & run

```bash
swift test            # 73 tests
swift build           # compile check
./build-app.sh        # → build/Mustard.app (ad-hoc signed, double-clickable)
open build/Mustard.app
```

`MustardApp` builds the container, owns the `AgentService`, the floating
`HoverPanel` (⌘⇧H), the `NotchController` (⌘⇧N), and a 60s scheduled-sweep loop.
Data persists to `~/Library/Application Support/Mustard/mustard.store`.

## The agent / Claude subscription (critical)

The worker shells out to `claude -p "<prompt>" --output-format json` with a
**scrubbed environment** (all `ANTHROPIC_*` and `CLAUDE*` vars removed) and
**closed stdin** — both are load-bearing (see ADR-0003 and the comments in
`ClaudeRunner.swift`). It uses whatever subscription the `claude` CLI is logged
into on this machine. If runs 401, the CLI token expired: `/login` in a terminal,
or mint a long-lived one with `claude setup-token`. Run serially; this is anchored
to Leon's Mac (cannot move to a cloud server without re-introducing API billing).

## The agent loop & trust (the product's core)

Sweep (manual or scheduled) → Claude proposes ≤5 **Recommendations** (each with
`confidence`, `reasoning`, an editable `draft`, an `action_type`) → you triage in
the Agent console (Approve · Edit · Change action · Comment · Schedule · I'll do it
· Snooze · Reject) → approved items **execute** via `claude -p` → every execution
produces exactly one **OutputCard** (no silent completion) → you review (Accept ·
Revise · Discard). **Trust** (Manual/Supervised/Trusted/Autonomous) × **confidence**
decides auto-run; email/Slack/ticket actions are **always gated** regardless
(`TrustPolicy`, `RecommendationAction.isGated`). Tunable knobs:
`TrustPolicy.autoConfidenceThreshold` and `RecommendationAction.isGated`.

## Git / PR conventions

- Work on a branch; never commit straight to `main` for feature work.
- Commit messages: `type(scope): summary`, end with the Co-Authored-By trailer.
  Commit in bite-sized, test-passing steps.
- A change is "done" only when `swift test` passes and `swift build` succeeds —
  state the evidence, don't assert success without it.
- Plans live in the sibling Triage-tool repo under
  `docs/superpowers/plans/` (historical) and now `docs/build-order.md` here.

## Workflow gates (project-bootstrap discipline)

| Gate | Who | When |
|------|-----|------|
| Spec approved | Leon | before any feature code |
| Plan approved | Leon | before implementation |
| PR reviewed | Leon | before merge |
| Outward actions confirmed | Leon | creating remote repo / tracker / backend / push |

## Out of scope (YAGNI) — deliberately not built

Multi-user/auth/billing; a hosted backend (no Supabase/Node — see ADR-0001);
web app; per-token API usage; email/Slack/meeting *sources* (only the vault source
exists — fields are modelled, not wired); live Google Calendar fetch (data layer
done, awaits Leon's OAuth client id); CloudKit sync + iOS target (schema is ready;
needs an Xcode project for entitlements — see ADR-0004).

## Agent Loop Workflows

This repo uses Leon's `dev-loop` plugin for autonomous development.

### Human Role

Leon sets product direction at kickoff and accepts the risk of irreversible outward
actions. Leon is NOT the engineering reviewer and is NOT a per-PR gate.

### Workflow Files

Read before running dev-loop workflows:

- `.agent-loop/project.yml` — repo identity, PR target, autonomy kill-switch
- `.agent-loop/checks.yml` — required verification commands (`swift test`, `swift build`)
- `.agent-loop/risk.yml` — task-label / path risk + irreversible outward actions
- `.agent-loop/review-rubric.md` — fresh-context review requirements
- `.agent-loop/done-criteria.md` — what must exist before merge

### How Work Lands

- Builders create branches, commits, PRs, and merges autonomously.
- Required checks from `.agent-loop/checks.yml` must pass.
- A fresh-context review (separate session) must pass before merge.
- Low/medium-risk changes auto-merge.
- High-risk changes auto-merge only after the `deep-review` adversarial panel passes;
  if the panel finds a blocker, the merge is held and logged to the digest.
- Irreversible outward actions (publish release, delete remote data, rotate secrets,
  force push) stop for Leon's explicit yes/no — the only human gate.
- Every merge or hold is appended to `.agent-loop/digest.md` with a ready `git revert`
  line, so Leon can scan and undo anything after the fact.

### Runtime Artifacts

Each run writes under `.agent-loop/runs/<run-id>/`: at minimum `trace.jsonl`,
`verification.md`, review reports, `risk-report.md`, `deep-review-report.md` (high
risk), and `pr-body.md`.
