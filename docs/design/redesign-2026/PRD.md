# Mustard 2026 Redesign — PRD

**Status:** approved (kickoff 2026-07-01) · **Tracker:** Linear `BAK` / project Mustard · **Milestones:** `Redesign · Desktop delta`, `Redesign · iOS foundation`, `Redesign · iOS companion`

This document is the destination spec for the 2026 desktop + mobile redesign. The
visual + behavioural **source of truth** is the vendored prototype package in this
folder:

| File | Surface |
|---|---|
| `README.md` | The handoff spec (concepts, screens, state model, design tokens). |
| `Mustard.dc.html` | Desktop app — all four screens + Settings + chrome. |
| `Mustard Mobile.dc.html` | iOS companion — bottom-tab app. |
| `MustardBoardCard.dc.html` | Desktop board card component. |

The `.dc.html` files use an in-house prototyping runtime (`support.js`) and device
bezel (`ios-frame.jsx`) that are **deliberately not vendored** — they are not
product code. Treat the HTML as the visual/behavioural reference and lift exact
values (hex, spacing, type, copy, interactions) from it; recreate in SwiftUI using
existing `MustardKit` components and patterns.

---

## Problem

Mustard already plans your day and your agent's day together, but the shipped UI
predates this high-fidelity design pass. The redesign brings the macOS app up to
the handoff, and adds a first **iPhone companion** so triage and review work away
from the Mac.

## Baseline — already shipped (do NOT rebuild)

A codebase audit (2026-06-30) found most of the design's model + desktop surface is
already implemented. These are **built** and only need parity verification, not
reconstruction:

- **Stage machine** — `TaskStage` (inbox, planned, scheduled, forAgent,
  needsApproval, queued, needsReview, inProgress, blocked, done).
- **Owner** (`TaskOwner` me/agent) + hand-over / take-back.
- **Two gates** (needsApproval, needsReview) + **gated** actions + 🔒 (`isGated`,
  `TrustPolicy`).
- **Trust** (Manual/Supervised/Trusted/Autonomous) + blurbs.
- **Recommendation** model + the triage→board **spawn loop** (`AgentService.decide`,
  `recToStage`).
- **Board** — owner-segmented columns, area chips, drag-to-restage; **board card**
  (`MustardBoardCard`) built to this handoff (BAK-79).
- **Task detail** slide-over + **create/edit** form.
- **Agent console** two-pane + RE-BUCKET chips; review lives on the board's Needs
  Review column (ADR-0010).

## Desktop delta (milestone: `Redesign · Desktop delta`)

The genuine missing work on the shipped app:

- **BAK-97** *(this issue)* — vendor handoff + PRD.
- **BAK-98** — design-token consolidation; pin confidence thresholds; fix Admin dot.
- **BAK-99** — card: priority flag, ✦ Proposed pill, tags row.
- **BAK-100** — board inline hover gate actions + detail reverse transitions (Hold,
  Request changes).
- **BAK-101** — board review-focus mode ("N waiting on you").
- **BAK-102** — board column polish (auto-collapse empties, per-column +Add).
- **BAK-103 / 104** — Today: progress bar + Plan entry + quick-add / agent nudge.
- **BAK-105 → 109** — Week: capacity + load bars + time-of-day grouping → ✦ Balance.
- **BAK-106** — agent co-pilot dock (bottom bar; not in the handoff README).
- **BAK-107** — task-to-task `blockedByTask` dependency.
- **BAK-111 / 112 / 117 / 118** — parity audits (console, settings, board, detail/form).
- Reused: **BAK-49** (areas/lists UI), **BAK-51** (recurrence).

## iOS companion (milestones: `iOS foundation`, `iOS companion`)

- **BAK-108** — iOS app target + SPM→Xcode migration (ADR-0004). **HIGH risk,
  blocked on Apple Developer entitlements.** Everything mobile chains off this.
- **BAK-110** — app shell (bottom-tab nav, agent badge, FAB, shared filter state).
- **BAK-113 / 114 / 116 / 119** — mobile Today / Board (stacked sections) / Week
  (day-strip) / Triage (swipe deck).
- **BAK-115** — shared task-detail + triage-detail bottom-sheets.

The mobile companion reuses the platform-agnostic `MustardKit` (Models/Logic/Agent);
only Views are new. There is **no create/edit form, no Settings, no sidebar/dock**
on mobile (desktop-only). `BAK-46` (CloudKit sync) is a separate capability flip
layered on the iOS target.

## Implementation decisions

- Pure decision logic (capacity, balance, derivations, spawn rules) lives in
  `Logic/`/`Agent` and is **TDD** with a pinned UTC `Calendar` + ISO fixtures.
  Views only render and dispatch (per CLAUDE.md).
- Mobile and desktop share one model + stage machine + spawn loop in `MustardKit`;
  platform-specific surfaces are desktop drag-and-drop / create-edit form /
  two-pane console / dock vs mobile swipe deck / bottom-sheets / day-strip / tab bar.

## Testing decisions

- New behaviour in `Logic/`/`Agent`/`Calendar`: failing XCTest first.
- Required checks: `swift test` + `swift build` (`.agent-loop/checks.yml`).
- Views verified by build + Leon's eye (the in-session shell can't screenshot the
  native app).

## Discrepancies to pin (resolve in BAK-98)

1. **Confidence-colour thresholds** drift — handoff README says ≥0.5 → amber;
   desktop code used ≥0.7 green / ≥0.4 amber / else red in two views while the board
   card used ≥0.5; mobile uses ≥0.5. The **≥0.7 green / ≥0.5 amber** set is canonical.
   **✅ Resolved in BAK-98:** `Theme.confidenceTier`/`confidenceColor` (≥0.7/≥0.5) is
   the single source; `RecommendationDetailView` + `AgentConsoleView` now call it.
2. **Admin area-dot colour** — correct is `#3E8E7E` (green); the seed coloured it
   blue (Admin inherited the "Code Heroes" Area colour).
   **✅ Resolved in BAK-98 (seed):** PreviewData gives Admin its own green Area.
   **Deferred:** Mustard colours dots **by Area**, the handoff **per list**; exact
   per-list colour under one group header (Errands purple vs Reading grey under
   "Personal") needs a per-list `colorHex` — a model change, not done here.

## Known stale-spec notes

- The prototype + this README describe a **console-resident Review queue** (Agent
  screen) with Accept/Revise/Discard cards. The shipped app moved review to the
  **board's Needs Review column (ADR-0010)**; the console intentionally omits the
  queue. Treat the README's console Review section as superseded — do not re-flag in
  parity audits (BAK-111).

## Out of scope (YAGNI)

Multi-user/auth/billing; hosted backend; web app; configurable gated-action rules
(not in the prototype); mobile create/edit form; off-Mac agent execution. See the
repo's ADRs and CLAUDE.md "Out of scope".
