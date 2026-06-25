# Ownership badge (needs me vs agent has it) — design

- **Date:** 2026-06-26
- **Status:** Approved (design); ready for implementation plan
- **Scope:** Enrich the existing per-task `DelegationBadge` so every row instantly reads "needs me" vs "the agent has it", and fold the redundant owner indicators into that one badge. Surfaces: Today (`TimelineRow`), Board (`BoardCard`), Week (`WeekChip`). Calm-first per ADR-0005.

## Problem & context

The you→agent delegation loop (I1) shipped: tasks carry `delegation: Recommendation?`, and `DelegationPhase.of(task)` derives `.proposed / .working / .awaitingReview / .done`, rendered by `DelegationBadge` in agent-purple. Two gaps remain:

1. **Redundancy.** A delegated task shows two purple `cpu` signals — a standalone owner indicator (`Label("Agent")` in `TimelineRow`; a leading `cpu` icon in `WeekChip`) **and** the `DelegationBadge` phase. (`BoardCard` already shows only the badge.)
2. **No "needs me" signal.** Every phase renders in the same purple, so the one moment that's actually on you — the agent finished, review its output — doesn't stand out, and a proposal awaiting your approval looks identical to the agent quietly working.

The data to fix this already exists — **no model migration**: `owner`, the `delegation` link, and the phase resolver are all in place. This is a Bond-inspired idea (their `NEEDS YOU` vs `DELEGATED` split) translated into Mustard's calm aesthetic — see `docs/research/2026-06-25-bond-competitive-analysis.md` (steal-list B).

Key constraint (ADR-0005, "Things 3 calm"): density from hierarchy, not cramming. So the rule is **badge only when the agent is involved** (your own tasks stay bare), and let only the "needs you" states wear an attention colour.

## Decisions

| # | Decision | Rationale | Rejected |
|---|----------|-----------|----------|
| 1 | One badge per row is the **sole** owner/agent signal | Kills the double-`cpu` redundancy; one place to reason about ownership | Keep separate owner label + phase badge (today's redundancy) |
| 2 | Badge only for agent-involved tasks; your own tasks stay bare | Calm — don't badge the default majority of rows | `NEEDS YOU` on every one of your tasks (Bond does this; too noisy for a single-user planner) |
| 3 | Two visual weights via a pure `DelegationTone` | The "which treatment per phase" decision is testable in `Logic/`, per the separation rule — not buried in the view | Switch on phase inside the view (decision escapes `Logic/`, untestable) |
| 4 | `proposed` + `awaitingReview` → **needsYou** (amber); `working` → **agentHasIt** (purple); `done` → **doneByAgent** (grey) | Amber = "ball's in your court" (approve-to-run, review-output). Purple = agent's got it, ignore. Reuses the purpose-built `warning` amber and leaves blue as the pure action accent | `proposed = purple` (considered — nothing runs until you approve, so it is genuinely on you → amber wins) |
| 5 | Rename `awaitingReview` label `"Awaiting review"` → `"Your turn"` | Action-oriented "needs you" nudge; the label is consumed **only** by the badge (verified — `TimelineRow.swift:6` is the sole reader) | Keep "Awaiting review" |
| 6 | Fallback: a plain purple `Agent` badge when `owner == .agent` but no active phase | Lets us delete the standalone labels without losing the agent signal in the edge case (rec nulled by delete-rule, or owner set manually) | Leave the standalone label for that case (re-introduces the redundancy) |
| 7 | Add two `Theme.Palette` amber tokens (`warningSoft`, `warningDeep`) | The amber pill needs a light background + dark-enough text for contrast, and should live in the token system | Inline `warning.opacity(…)` (marginal contrast, off-system) |

## Architecture

Separation rule (CLAUDE.md): the **decision** (phase → tone, labels) is pure and unit-tested in `Logic/`; the view only maps tone → SwiftUI style and renders.

### `Logic/DelegationPhase.swift` — extend (pure, TDD'd)

Add the tone enum + property; change one label.

```swift
public enum DelegationTone: Equatable { case agentHasIt, needsYou, doneByAgent }

extension DelegationPhase {
    /// Visual weight for the row badge. nil ⇒ no badge.
    public var tone: DelegationTone? {
        switch self {
        case .none: nil
        case .proposed, .awaitingReview: .needsYou   // ball is in your court
        case .working: .agentHasIt                    // agent on it; you can ignore
        case .done: .doneByAgent                      // quiet, informational
        }
    }
}
```

And in `label`: `case .awaitingReview: "Your turn"` (was `"Awaiting review"`). `.proposed` keeps `"Proposed"`.

### `Logic/Theme.swift` — add two tokens

```swift
public static let warningSoft = Color(hex: "#FAEEDA") // amber pill background (needs-you)
public static let warningDeep = Color(hex: "#633806") // amber pill text (needs-you)
```

### `Views/TimelineRow.swift` — rework `DelegationBadge`; drop the standalone label

```swift
struct DelegationBadge: View {
    let task: MustardTask
    var body: some View {
        let phase = DelegationPhase.of(task)
        if let label = phase.label, let tone = phase.tone {
            content(label, tone)
        } else if task.owner == .agent {
            content("Agent", .agentHasIt)            // agent-owned, no active phase
        }
    }

    @ViewBuilder private func content(_ label: String, _ tone: DelegationTone) -> some View {
        switch tone {
        case .agentHasIt:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.agent)
        case .needsYou:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.warningDeep)
                .padding(.vertical, 1).padding(.horizontal, 8)
                .background(Theme.Palette.warningSoft, in: Capsule())
        case .doneByAgent:
            Label(label, systemImage: "checkmark")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
```

Then in `TimelineRow.body`, **delete** the standalone owner label (`if task.owner == .agent { Label("Agent", systemImage: "cpu")… }`, ~lines 55–58). `DelegationBadge` now carries it.

### `Views/WeekView.swift` — drop the leading `cpu` icon

In `WeekChip`, delete the leading `if task.owner == .agent { Image(systemName: "cpu")… }` (~lines 254–256). The trailing `DelegationBadge(task:)` already present now carries the signal.

### `Views/BoardView.swift` — no edit

`BoardCard` already renders only `DelegationBadge(task:)` (~line 113); it inherits the new treatment for free.

## Testing

- **TDD (`Logic/`):** extend `Tests/MustardTests/DelegationPhaseTests.swift`:
  - `tone`: `.none`→nil, `.proposed`→`.needsYou`, `.working`→`.agentHasIt`, `.awaitingReview`→`.needsYou`, `.done`→`.doneByAgent`.
  - label: `.awaitingReview` `.label == "Your turn"`.
- **Build + eye (`Views/`):** `swift build`, then `./build-app.sh && open build/Mustard.app`. Verify on Today/Board/Week: a delegated task shows **one** badge cycling Proposed (amber) → Agent working… (purple) → Your turn (amber) → Done by agent (grey); your own tasks show no badge; no double-`cpu`. Per CLAUDE.md the agent can't screenshot the native app — state it builds and runs; Leon confirms the look.

## Out of scope (v1)

- Notch waiting-count tinting by needs-you count. (Follow-up.)
- Agent-**returned**/declined tasks (owner reverted to `.me`): already resurface in your list with an appended note; no badge. (Follow-up.)
- Priority / provenance on the row (separate steal-list items; deliberately not bundled here).
- Multi-agent "Delegated to X" (Direction B) — only meaningful once more than one delegate exists.

## Self-review

- **Placeholders:** none.
- **Consistency:** tone mapping (Decision 4) matches the `Logic` code and the test list; the label rename (Decision 5) matches code + test + the verified single reader.
- **Scope:** one implementation plan; small — one `Logic` extension, two tokens, two view edits, one test file. `BoardView` unchanged.
- **Ambiguity:** "needs you" = `proposed` + `awaitingReview` (explicit). The icon set (`cpu`/`checkmark`) may be refined at eye-check — noted, not a blocker.
