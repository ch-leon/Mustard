# Mustard

A native macOS command centre that plans your day and your AI agents' day together.
Spec: "Personal Productivity Tool — Feature Spec v2" (Obsidian). Design language:
Things 3 calm — warm off-white, hairline dividers, one blue accent.

## Run

```bash
swift test          # 20 tests: models, DayPlanner, agent loop, runner spawn path
./build-app.sh      # builds build/Mustard.app (signed, double-clickable)
open build/Mustard.app
```

## What works (v0)

- **Today** — timeline of scheduled tasks, quick capture (Enter schedules onto
  today 9:00), complete/uncomplete, inbox of unscheduled tasks, carry-forward of
  open past tasks. SwiftData-persisted to `~/Library/Application Support/Mustard/`.
- **Agent** — point it at your Obsidian vault (Choose…), hit **Sweep**: Claude
  reviews the vault and proposes up to 5 tasks into the **Recommendations**
  queue. Decide each: **Approve** (agent executes now) · **Schedule** (becomes a
  task tomorrow 9:00) · **I'll do it** (becomes an inbox task) · **Deny**. Every
  execution produces an output card in the **Review** queue: **Accept · Revise ·
  Discard**. No silent completion.
- **Hover panel** — ⌘⇧H: always-on-top, non-activating mini panel showing your
  current focus (or what the agent is executing) and how many items wait on you.
  Expands on hover.

Agents run through your **Claude subscription** (`claude -p`, headless) — no API
key, no metered billing. If runs fail with 401, run `/login` inside `claude`
once (tokens expire), or mint a long-lived one with `claude setup-token`.

## Architecture

Swift Package: `MustardKit` (models, logic, agent layer, views) + thin `Mustard`
executable + `MustardTests`. SwiftData schema is CloudKit-compatible (optional
relationships, no unique constraints) so iCloud sync is a later capability flip.
`ClaudeRunner` spawns the CLI with a scrubbed env (`ANTHROPIC_*`/`CLAUDE*`
removed) and closed stdin; override the binary with `MUSTARD_CLAUDE_BIN` (tests
use a stub script).

## Next (per spec §13)

Sources beyond the vault (email/Slack/meetings) · gating + per-agent trust ·
the notch surface · Google Calendar two-way · CloudKit + iOS companion.
Plans live in `Triage-tool/docs/superpowers/plans/`.
