# Mustard — Developer Handoff

Mustard is a **native macOS productivity command-centre** that plans your day *and your AI agent's day* together. The differentiator is the **agent co-planning loop**: the agent proposes work, you triage it, approved work becomes real tasks, and any agent task that touches the outside world passes through **two human gates** before it counts.

This package contains the **high-fidelity design** as interactive HTML prototypes plus this spec. The real app is **SwiftUI / macOS** (with an iOS companion) — recreate these designs using the codebase's existing components and patterns. **Do not port the HTML/JS literally**: the `.dc.html` files use an in-house prototyping runtime (`support.js`) and a custom template syntax that is not production code. Treat the HTML as the visual + behavioural source of truth and lift exact values (hex, spacing, type, copy, interactions) from it.

## Files
| File | What it is |
|---|---|
| `Mustard.dc.html` | **Desktop app** — window chrome, sidebar, and all four screens (Today, Board, Week, Agent) + Settings. The canonical, most complete surface. |
| `Mustard Mobile.dc.html` | **iOS companion** — bottom-tab app with the same four screens adapted for one-thumb use, inside an iPhone bezel. |
| `MustardBoardCard.dc.html` | The desktop board task-card component (presentational; receives a computed view-model). |
| `ios-frame.jsx` | Device-bezel wrapper used by the mobile prototype (prototype scaffolding — not part of the product). |
| `support.js` | Prototype runtime (reference only — **never ship**). |

To preview: open `Mustard.dc.html` or `Mustard Mobile.dc.html` in a browser.

---

## Core concepts

### Ownership
Every task has an **owner**: **you** (`me`) or the **agent** (`agent`). You can hand a task to the agent or take it back at any time. Agent tasks are tinted purple (`#7F77DD`) and carry a left accent border on cards.

### The pipeline (`stage`)
A task's `stage` is its position in the workflow. Your tasks and agent tasks share one set of stages:

| stage | Label | Belongs to | Notes |
|---|---|---|---|
| `inbox` | Inbox | both | Uncategorised. Agent-*proposed* tasks land here flagged "✦ Proposed". |
| `planned` | Planned | you | Backlog. |
| `scheduled` | Scheduled | you | Has a day/time. |
| `forAgent` | For Agent | agent | You handed it over; the agent gathers context / drafts before proposing. Optional step. |
| `needsApproval` | Needs Approval | agent | **GATE 1** — you approve before the agent runs it. |
| `queued` | Approved · Queued | agent | Approved, will run. |
| `needsReview` | Needs Review | agent | **GATE 2** — you check the output before it counts. |
| `inProgress` | In Progress | you | Your active work. |
| `blocked` | Blocked | you | Carries a `reason`. |
| `done` | Done | both | Complete. |

**Agent lifecycle:** `For Agent → Needs Approval (gate 1) → Approved·Queued → Needs Review (gate 2) → Done`. (An earlier "Agent Running" stage was intentionally removed — there is no live-progress column.)

### The two gates & gating
- **Gate 1 (Needs Approval):** nothing the agent does runs until you approve.
- **Gate 2 (Needs Review):** the agent's output waits for you to accept before it's final.
- A task flagged **`gated`** is one whose action affects the outside world (send email, post to Slack, chase an invoice, file a ticket). **Gated actions ALWAYS require explicit approval, regardless of trust level** — even fully autonomous. Render the 🔒 wherever a gated task/recommendation appears. Internal-only work (drafting, summarising, scheduling, archiving) is not gated and may auto-run at higher trust.

### Trust levels
A global setting governs how much runs without you: **Manual → Supervised → Trusted → Autonomous**. Higher = more auto-execution of *non-gated* work; gated actions always pause. (Surfaced in the Agent header pill and Settings.)

### Triage → Board (the loop)
Recommendations the agent surfaces (desktop **Agent** console; mobile **Triage** swipe deck) resolve into **real board tasks**:
- **Approve** an agent action → spawns an `agent` task at `needsApproval` (gated) or `queued` (non-gated).
- **Schedule** → your task at `scheduled`. **I'll do it** → your task at `planned`. **Reject / Snooze** → nothing spawned.
- A confirmation toast ("Added to board · {stage}") appears; desktop links **View →** to the new task.

---

## Screens

### 1. Today
Single-column day view (max-width ~720px desktop).
- Header: "Today" + date + **"✦ Plan"** entry to the Agent console; a thin **day-progress bar** ("N of M done").
- A dismissible **agent nudge** ("Agent has N things for you") when the triage queue is non-empty.
- **Timeline list:** each row = time gutter (left, `#B0ACA1`) + a check circle (tap to complete; agent tasks' circle is purple-bordered; meetings show 🗓 instead) + title + meta (agent tag, area dot+name, estimate, "Join ↗" for joinable meetings, and a gate-status pill like "Approve"/"Review" for agent tasks). Tapping a row opens the **task detail panel**.
- **Inbox** section beneath for unscheduled `inbox` tasks.
- Completed tasks: strikethrough, muted, green check.

### 2. Board (owner-segmented pipeline) — the centrepiece
- Header: "Board" + **"N waiting on you"** pill (count of `needsApproval` + `needsReview` in the current filter; click → focuses the board to just those two gate columns; toggles to "Exit review queue"). Right side: Search, **"+ New task"**.
- **Owner segmented control:** `Everyone` / `Mine` / `✦ Agent` — switches which columns show:
  - Mine → `inbox, planned, scheduled, inProgress, blocked, done`
  - Agent → `inbox, forAgent, needsApproval, queued, needsReview, done`
  - Everyone → all 11, in pipeline order.
- **Area chips:** All / DLA SDK / Admin / Personal (Personal = errands + reading). Combine with owner (AND). Sidebar area rows also drive this filter.
- A one-line **caption** explains the current view.
- **Columns** (horizontal scroll): fixed 182px, fill window height, scroll independently. Header = colour accent bar + UPPERCASE label + count + optional sub-label. Column styling by "kind" (default/handoff/gate/agent/warn/done) — see tokens. In the **Everyone** view, empty columns **auto-collapse** to thin vertical labelled strips (click to expand).
- **Drag** any card to another column to change its stage; dropping on an agent stage also reassigns ownership to the agent. Columns highlight on drag-over.
- **Inline gate actions:** hovering a Needs-Approval or Needs-Review card reveals quick **✓ Approve & run / ✓ Accept** + **Deny / Discard** buttons.

#### Task card (`MustardBoardCard`)
Top row: **priority flag** (HIGH/URGENT) · hover-revealed **You↔✦ owner toggle** · "✦ Proposed" pill · 🔒. Then **title**. Then meta (area dot+name, source badge, due — red if overdue). Then tags (`#tag`). Then, by stage: a **confidence** row (numeric + 5 segment bars) for Needs-Approval/proposed, a **status pill** ("Your move · approve to run", "Queued to run", "Review output", "Preparing"/"Waiting for agent"), or a blocked reason. Cards are `cursor:grab` (draggable). Tap → detail panel.

#### Detail / approval panel (right slide-over, shared by Today / Board / Week)
Stage badge · **Edit** link · title · description · 🔒 gated notice · confidence · **WHY** rationale · **what the agent will do** / **draft** / **agent output** (green-tinted) depending on stage · **DETAILS** list (Assignee, Stage, Priority, Area, Estimate, Due, Scheduled, Repeats, Parent, Blocked-by) · **tags** · interactive **subtask** checklist with progress. Footer actions adapt to stage:
- Needs Approval → **Approve & run** / I'll do it / Deny
- Needs Review → **Accept output** / Request changes / Discard
- Proposed inbox → **Approve** / Schedule / I'll do it / Dismiss
- For Agent → **Take back**
- Queued → **Move to review** / Hold
- Your tasks → **Mark done** / Hand to ✦ agent

#### Create / edit task (right slide-over)
Title + description, then a label-row form: **Stage** (full pipeline incl. agent stages), **Priority** (Low/Normal/High/Urgent), **Assignee** (Me/Agent), **Due** + **Scheduled** toggles with date fields, **Estimate** (15m–1d), **Parent**, **Recurrence** (None/Daily/Weekly/Monthly), **Tags** (type+Enter chips), **Blocked by**, **Area**, and a **Subtasks** add/check/remove list. Create disabled until a title exists. Edit adds **Delete**. (Dates/parent are free-text in the prototype — wire to real pickers / task search.)

### 3. Week (hybrid planner)
- Header: "Week" + date nav + owner filter (Everyone/Mine/✦Agent) + area chips + **"✦ Balance"**.
- Left **Unscheduled rail** + seven **day columns** (Mon–Sun, today tinted). Each day header shows **capacity** (summed estimate hours of open tasks) with a load bar coloured green→amber→red (overloaded > 8h). Within a day, tasks group under **Morning / Afternoon / Evening / Anytime**. Agent blocks tinted purple.
- **Drag-to-schedule:** drag from the rail onto a day (schedules it), between days (moves), or back to the rail (unschedules). Click any block → detail panel.
- **✦ Balance:** an agent action that redistributes movable tasks (skips meetings + done) greedily across Mon–Fri to flatten overloaded days; shows a toast with an **Undo** that restores the prior layout exactly.

### 4. Agent console (desktop) / Triage (mobile)
- Source rows (knowledge base / meetings), a **Sweep** action, and a **Trust** segmented control (Manual→Autonomous) with a plain-English explanation of what each level runs.
- **Recommendations** (master list + detail on desktop; **Tinder-style swipe deck** on mobile — → approve, ← deny, ↑ I'll do it). Each recommendation detail shows: source badge, action-type pill, confidence, **WHY**, a **RE-BUCKET** chip row (Draft email / Draft Slack / Create task / Update vault / Shortcut ticket / FYI / Ignore), **PROPOSED DRAFT**, a **Feedback to the agent** input, and actions **Approve · Comment · Snooze · Schedule · I'll do it · Reject**.
- **Review** queue: agent outputs awaiting accept/revise/discard.
- All decisions feed the **Triage → Board** loop above.

### Settings
Source connections + the global **Trust** control + (future) configurable gated-action rules.

---

## State model

One shared `tasks` array drives every screen. A task:
```ts
{
  id: string,
  title: string,
  description?: string,
  owner: 'me' | 'agent',
  stage: 'inbox'|'planned'|'scheduled'|'forAgent'|'needsApproval'|'queued'|'needsReview'|'inProgress'|'blocked'|'done',
  list?: 'dla'|'admin'|'errands'|'reading' | null,   // area
  priority?: 'low'|'normal'|'high'|'urgent',
  day?: number | null,        // 0=Mon … 6=Sun (week placement / Today = day 4 in the demo)
  time?: number,              // minutes since midnight
  est?: number,               // estimate in minutes  (or `estimate`: '15m'|'30m'|…'1d')
  due?: string, scheduled?: string, overdue?: boolean,
  recurrence?: 'daily'|'weekly'|'monthly',
  tags?: string[], parent?: string, subtasks?: {title,done}[],
  meeting?: boolean, joinable?: boolean,
  // agent fields:
  source?: 'gmail'|'xero'|'meeting'|'slack'|'linear'|'vault',
  conf?: number,              // 0..1 confidence
  gated?: boolean,            // outside-world action → always needs approval
  proposed?: boolean,         // agent-proposed, sitting in inbox
  preparing?: boolean,        // (forAgent) actively gathering context
  reason?: string,            // (blocked)
  actionType?: string, reasoning?: string, draft?: string, draftLabel?: string, output?: string, ask?: string
}
```
Counts, the "waiting" pill, the agent sidebar badge, and per-day capacity are all **derived** — keep them computed, never stored. Recommendations are a separate list that **spawns** tasks on decision.

---

## Design tokens

**Colour**
- Surfaces: app/card `#FBFAF7`; title bar/panels `#F4F1EA`; sidebar `#F7F4ED`; chip-active `#EAE5DB`; nav-active `#EDE9E0`.
- Window backdrop gradient: `linear-gradient(150deg, #e7e1d5, #d6cfc0, #cfc7b6)`.
- Hairline `#E7E3DA` (borders are `0.5px`); secondary divider `#E1DCD1`.
- Text: primary `#2B2A26`; secondary `#9A968B`; tertiary `#B0ACA1` / `#C0BCB1`; on-surface `#46433B` / `#5C584E`.
- Accent (blue, *you*): `#2D7FF9`. Agent (purple): `#7F77DD`; text `#6A61C9`; mid `#8079C6`; tints `#EEEBFA`,`#CFC9F0`,`#BCB6EC`,`#F3F1FA`.
- Done (green): `#1D9E75`; review text `#1B7A57` on `#E3F2EB`. Warn (amber): `#D98A29` / `#B07A29`.
- Area dots: DLA SDK `#2D7FF9`, Admin `#3E8E7E`, Errands `#7F77DD`, Reading `#B0ACA1`.
- Priority: HIGH `#A8502E` on `#F7E4D8`; URGENT white on `#C2603F`.
- **Confidence thresholds:** ≥0.7 → `#1D9E75`; ≥0.5 → `#BA7517`; else `#D85A30`. Unfilled segment `#E4DFD5`.
- Source badges: Gmail `#A8442E`/`#FBEAE4` · Xero `#1B6FA8`/`#E4F0FA` · Notes `#6A61C9`/`#EEEBFA` · Slack `#6A4FA0`/`#EFEAF7` · Linear `#54599A`/`#ECEDF7` · KB `#7B776C`/`#F1EDE4`.

**Column kinds (Board):** default `rgba(239,235,226,0.55)` (no accent, head `#9A968B`) · handoff tint+`#CFC9F0`/`#8079C6` · gate `rgba(127,119,221,0.085)`+`#7F77DD`/`#6A61C9` · agent tint+`#BCB6EC`/`#8079C6` · warn `rgba(217,138,41,0.07)`+`#D98A29`/`#B07A29` · done `rgba(29,158,117,0.05)`+`#9BD0BD`/`#6A9C84`.

**Type** — system stack (`-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui`). Screen title 24px/600/-0.01em (mobile 28px/700). Column header 11px/700 UPPERCASE +0.04em. Card title 13.5px. Card meta 11.5px. Status/confidence pills 10.5px/600. Section labels (WHY, DETAILS…) 10px/600 +0.08em `#B0ACA1`.

**Spacing / radius** — sidebar 208px; board columns 182px (compact 162px), gap 11px; slide-overs 430px wide. Radii: window 13px · column 12px · card 9px · buttons 8–9px · pills 20px · sheets 26px (mobile bottom-sheet). Borders `0.5px`; card left accent 2.5px; column accent bar 3px. Window shadow `0 32px 80px -24px rgba(40,34,24,0.45), 0 4px 14px rgba(40,34,24,0.16)`.

## Assets & icons
No image assets. All glyphs are Unicode (☀ ▦ ▤ ✦ ⌁ ✉ ◷ ◐ 🔒 🗓 ⚠ $ #) — replace with the codebase's icon set (SF Symbols for SwiftUI). The agent mark **✦** should map to one consistent agent icon throughout.

## Suggested build order
1. The shared **task model** + stage machine (with the two-gate transitions and ownership reassignment).
2. **Board** (pipeline columns, filters, card, detail/approval panel, create/edit) — highest-value, most reused.
3. **Today** and **Week** on the same model (Week adds capacity + drag-schedule + Balance).
4. **Agent console / Triage** + the **Triage→Board** spawn loop.
5. **Trust** + gated-action config in Settings.
