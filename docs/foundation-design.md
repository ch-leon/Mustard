# Mustard — Foundation Design

> Written retroactively (2026-06-13) in the shape project-bootstrap's Phase B would
> have produced up front, reconciled to what Mustard actually is. Source of truth
> for the foundation; feature specs/plans live alongside and link back here.

## Product

**Mustard** — a native macOS command centre that plans your day **and your AI
agents' day** together. Hybrid of Blitz (always-on hover), boring-notch (ambient
notch), Sunsama/Akiflow (day/week planner), Todoist/Things 3 (calm tasks).
Personal-first (one user, Leon), architected to *possibly* generalise later.

**The wedge:** every planner assumes you are the only worker. Mustard gives the
work your agents do a control surface — triage → recommendation → approval →
execution → review — on the same timeline as your own tasks.

## The six pillars (Leon's canonical feature list)

1. **Notch bar** — ambient; current task, next meeting, waiting count; hover expands.
2. **Always-on hover** — current focus + next-up tasks; never steals focus.
3. **Task management (me)** — Kanban/list, status taxonomy, edit/schedule/delete.
4. **Task management (agents)** — approval flow + output flow.
5. **Calendar** — meetings + tasks + reminders together.
6. **Day/week planner** — drag to time-box.

## Stack & foundation (see ADRs)

- Native **SwiftUI**, macOS 14+ (ADR-0002). Shared iOS codebase later.
- **SwiftData**, CloudKit-shaped (ADR-0001). Vault stays local markdown.
- Agent = **`claude` CLI subscription**, headless, Mac-anchored (ADR-0003).
- **Swift Package** now; Xcode project at the CloudKit/iOS step (ADR-0004).
- **"Things 3 calm"** design tokens, one file (ADR-0005).
- Auto-run = **confidence × trust**, always-gated outbound actions (ADR-0006).

## Repo & folder structure

See [`CLAUDE.md`](../CLAUDE.md#folder-layout) and [`architecture.md`](architecture.md).
Feature-folders within `MustardKit` (Models / Logic / Agent / Calendar / Views);
pure decision logic isolated in `Logic/` for unit testing; `docs/` holds this
design, the architecture reference, ADRs, and the build order.

## Testing & CI

- Logic/parsers are TDD (XCTest), time/zone pinned, network/process injected.
- Views verified by build + human eye (no native screenshots in the dev session).
- CI (`.github/workflows/ci.yml`): `swift build` + `swift test` on PRs to `main`.

## Workflow gates

Spec approved → Plan approved → PR reviewed; every outward action (remote repo,
tracker, backend, push) confirmed first. (Table in `CLAUDE.md`.)

## Out of scope (YAGNI)

Multi-user/auth/billing; hosted backend; web app; per-token API; email/Slack/
meeting *sources* (modelled, not wired); live Google Calendar fetch (data layer
done, awaits OAuth client id); CloudKit sync + iOS target (schema ready, needs
Xcode entitlements). Each is a deliberate later step, not an omission.

## Status snapshot (2026-06-13)

22 commits, 73 tests green. Built: foundation, agent loop (vault source), rich
triage cards, trust/gating, notch, hover, command bar, scheduled sweeps, Board,
Week, Today, task detail editor, Google Calendar data layer. Pending: live
calendar connect, more sources, CloudKit + iOS.
