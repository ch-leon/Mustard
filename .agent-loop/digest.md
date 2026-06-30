# Dev-loop Digest

Append-only ledger of merges and holds. Each entry carries a ready `git revert` line.

## 2026-07-01 — MERGED · BAK-131 contextual 'Approve & run' label (PR)
- **Risk:** low (Improvement; RecommendationDetailView label) · **Deep-review:** n/a
- **Checks:** swift build clean · swift test 417 pass/1 skip
- **Review:** fresh-context APPROVE — label-only, dispatch unchanged
- **Run:** `.agent-loop/runs/20260701-092733-bak-131-approve-labels/`
- **What landed:** rec-detail primary "Approve" → "Approve & run"; "& schedule" variant is the existing Schedule button.
- **Revert:** `git revert cd485be9409c879036e5d2b9459b698cca5f0965`


## 2026-07-01 — MERGED · BAK-130 agent console header subhead (PR)
- **Risk:** low (Improvement; AgentConsoleView header) · **Deep-review:** n/a
- **Checks:** swift build clean · swift test 417 pass/1 skip
- **Review:** fresh-context APPROVE — VStack-wrap balanced, agent.isSweeping valid, Theme tokens, no logic change
- **Run:** `.agent-loop/runs/20260701-092456-bak-130-subhead/`
- **What landed:** dynamic subhead under "Agent" ("reviewing your sources…"/"plans your day with you") + kept progress/toggle ("both").
- **Revert:** `git revert 59e1ca1d25326bb861b8d6fda1619491eebb03e3`


## 2026-07-01 — MERGED · BAK-132 Trust segmented control (PR)
- **Risk:** medium (Improvement; AgentConsoleView view-only — NOT TrustPolicy) · **Deep-review:** n/a
- **Checks:** swift build clean · swift test 417 pass/1 skip
- **Review:** fresh-context APPROVE — selection set closure byte-for-byte same dispatch (trustRaw + agent.applyTrust); no gating path touched (TrustPolicy/RecommendationAction diff empty); binding sound, no loop; Theme.agent tint
- **Run:** `.agent-loop/runs/20260701-092220-bak-132-trust-seg/`
- **What landed:** Trust dropdown Menu → `.segmented` Picker (active=purple); per-item blurb necessarily dropped (segmented has no subtitle) but the always-visible blurb card from BAK-112 covers it.
- **Revert:** `git revert afa6da4f251c480adb33fb6e2a2a34ad6e41730a`


## 2026-07-01 — MERGED · BAK-135 board drag-over column highlight (PR)
- **Risk:** low (Improvement; BoardView only) · **Deep-review:** n/a
- **Checks:** swift build clean · swift test 417 pass/1 skip
- **Review:** fresh-context APPROVE — isTargeted enter/leave guard avoids stuck dual-highlight; overlay scoped to full column (collapsed strips unaffected); drop handler unchanged; Theme.accent
- **Run:** `.agent-loop/runs/20260701-091958-bak-135-drag-highlight/`
- **What landed:** `.dropDestination(isTargeted:)` + `dropTargetStage` @State → 2px accent outline on the targeted column.
- **Revert:** `git revert 87c28f6fb5471834644efa6ed1345ab578e621a1`


## 2026-07-01 — MERGED · BAK-118 parity audit: detail + create/edit form (PR #52)
- **Risk:** medium (Improvement; TaskDetailSheet view edits + docs) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 417 pass/1 skip · CI (self-hosted)
- **Review:** fresh-context APPROVE — interactive subtasks toggle/remove correct + delete-safe (.nullify), progress recomputes, no ForEach-mutation reentrancy; assignee accent cosmetic; create/edit form strong parity
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-085104-bak-118-parity-detail/`
- **What landed:** docs/design/redesign-2026/parity/detail-form.md; inline fixes — interactive subtasks (toggle done + remove), assignee accent purple for agent. Follow-ups: BAK-136 (stage-adaptive footer matrix), BAK-137 (read-mode approval view).
- **Milestone:** completes the desktop-delta *audits*. Desktop redesign delta done except the spun-out polish follow-ups (BAK-130/131/132/133/134/135/136/137) + reused BAK-49/51.
- **Revert:** `git revert edaf153bde5c008505249ca180344363b8bbb7db`

## 2026-07-01 — MERGED · BAK-117 parity audit: Board + card (PR #51)
- **Risk:** medium (Improvement; cosmetic card/board views + docs) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 417 pass/1 skip · CI (self-hosted)
- **Review:** fresh-context APPROVE — presentation-only, no logic change; overdue branch sound, tag chips + hover-toggle correct (agent still shown via left accent), "All" label display-only; strong parity post-polish, no regressions
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-084538-bak-117-parity-board/`
- **What landed:** docs/design/redesign-2026/parity/board.md; inline fixes — overdue due red/amber+bold, tags as pill chips, owner toggle hover-revealed, "All areas"→"All". Follow-ups: BAK-134 (+New task + Search), BAK-135 (drag-over highlight).
- **Revert:** `git revert d47de79a375c237b379f11a017069ca51f7bbc0c`

## 2026-07-01 — MERGED · BAK-112 parity audit: Settings + Trust (PR #50)
- **Risk:** HIGH (path: TrustPolicy.swift) · **Deep-review:** PASS (3/3 clear — correctness, security/risk, spec)
- **Checks:** swift build clean · swift test 417 pass/1 skip · CI (self-hosted)
- **Deep-review:** copy-only change confirmed (gating predicates byte-for-byte unchanged; `blurb` is display-only); new blurb safety claims verified TRUE vs `isGated` model; all 5 strings byte-for-byte verbatim to the prototype. Report: deep-review-report.md.
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-083833-bak-112-parity-settings/`
- **What landed:** TrustPolicy.blurb aligned to handoff copy verbatim; always-visible trust blurb + gated footer note in the console; parity report. Follow-ups: BAK-132 (trust segmented control), BAK-133 (standalone Settings screen + per-source Connected).
- **Note:** HIGH was purely the path trigger; actual change is display copy. Honoured the panel anyway.
- **For Leon's eye:** trust blurb + gated footer note in the console.
- **Revert:** `git revert 9b6c02ee42c5dcab59fccbdc5f1b1bf43abcc903`

## 2026-07-01 — MERGED · BAK-111 parity audit: Agent console (PR #49)
- **Risk:** medium (Improvement; cosmetic views + docs) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 417 pass/1 skip · CI (self-hosted)
- **Review:** fresh-context APPROVE — presentation-only (✦ Sweep + action pill, WHY header, gated full-width banner), gated banner still `isGated`-gated, title HStack intact, Theme tokens, no logic change; parity report + ADR-0010 PRD note accurate
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-083219-bak-111-parity-console/`
- **What landed:** docs/design/redesign-2026/parity/agent-console.md (mostly MATCH); inline console parity fixes; PRD stale-spec note (console Review queue is board-side per ADR-0010). Follow-ups filed: BAK-130 (header subhead), BAK-131 (contextual approve labels).
- **Revert:** `git revert d3c4912bee8c8f0768d5446a6b12c7587b5f8dd8`

## 2026-07-01 — MERGED · BAK-107 blockedByTask dependency (PR #48)
- **Risk:** medium (Feature; additive SwiftData relationship + detail/form) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 417 pass/1 skip (+4 BlockedByTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — additive optional relationship is lightweight-migration-safe (existing stores decode nil; container model list unchanged), third self-ref unambiguous (no inverse), isBlocked non-recursive, .nullify delete-safe, cycle can't hang
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-082656-bak-107-blockedby/`
- **What landed:** `MustardTask.blockedByTask` (`@Relationship(.nullify)`, optional, CloudKit-safe); isBlocked derives from an unfinished blocker (free-text path kept); `BlockedByPicker` + "Blocked by" row in the detail/create-edit form (search, excludes self+done).
- **For Leon's eye:** Blocked-by picker + blocked treatment on the board.
- **Revert:** `git revert 63203df21edc9103a778278603ddd5672d5815e8`

## 2026-07-01 — MERGED · BAK-106 agent co-pilot dock (PR #47)
- **Risk:** medium (Feature; AgentInbox helpers + RootView) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 413 pass/1 skip (+4 dockText tests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — dockText pluralization/empty/joiner correct + tested, counts consistent with sidebar badge by construction (same helpers), dock hidden on .agent (no loop), layout sound (sibling in VStack, fills height)
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-082308-bak-106-dock/`
- **What landed:** `AgentInbox.pendingRecCount/outputCount/dockText`; RootView persistent bottom co-pilot dock (purple dot + Agent + derived text + "Open console →") on every screen except the Agent console. (Prototype surface not in the README.)
- **For Leon's eye:** dock bar placement + Open console link.
- **Revert:** `git revert 00979c1d9772ea1bc77b86901bf8a4e395280ac8`

## 2026-07-01 — MERGED · BAK-109 Week ✦ Balance + Undo (PR #46)
- **Risk:** medium (Feature; WeekPlanner algorithm + WeekView) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 409 pass/1 skip (+6 WeekBalanceTests) · CI (self-hosted)
- **Review:** round 1 CHANGES-REQUESTED — greedy LPT could land on a peak ≥ input while toast claimed success (reviewer fuzz-found). **Fixed:** no-regression guard (commit only if newPeak < currentPeak; else "already balanced") + regression test ({30,30}|{20,20,20} → LPT would hit 70, guard holds 60). Round 2 APPROVE — guard apples-to-apples, no new edge bugs, regression test genuine.
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-081411-bak-109-balance/`
- **What landed:** `WeekPlanner.balance(_:weekdays:)` (LPT + no-regression guard, BalancePlan/BalanceMove with prior date for exact Undo, excludes done/meetings, preserves time-of-day); WeekView "✦ Balance" button + dark toast + Undo (auto-dismiss 6s).
- **Known non-blocking:** when the heuristic can't improve an imbalanced layout it still says "already balanced" (cosmetic wording).
- **For Leon's eye:** Balance button + toast + Undo restore.
- **Revert:** `git revert 2f20549208e43dbda7e3f7f254d8dec35af75cdb`

## 2026-07-01 — MERGED · BAK-105 Week capacity + load bar + time-of-day grouping (PR #45)
- **Risk:** medium (Feature; WeekPlanner logic + WeekView) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 403 pass/1 skip (+5 WeekCapacityTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — tier boundaries (360/480) + label + timeOfDay + grouping all tested; capacityMinutes clock-independent (no done/double-count); Theme bar colours match handoff; ForEach id:\.0 safe
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-080709-bak-105-week-capacity/`
- **What landed:** `WeekPlanner.capacityMinutes/loadTier/capacityLabel/timeOfDay/groupByTimeOfDay`; WeekView day header capacity label (tier-coloured) + load bar; non-axis tasks grouped Morning/Afternoon/Evening/Anytime. Shared logic mobile Week (BAK-116) reuses.
- **Known non-blocking:** header capacity counts open tasks incl. agent-owned + a past-day-vs-column edge (spec says "open tasks"); String(format) locale separator (en-only app).
- **Unblocks:** BAK-109 (Week ✦ Balance).
- **For Leon's eye:** load bar colours + time-of-day section headers.
- **Revert:** `git revert 05f79d3a68807b7ba8b9dfae0acfe43651eb6cbd`

## 2026-07-01 — MERGED · BAK-104 Today dismissible agent nudge (PR #44)
- **Risk:** medium (Feature; shared Logic helper + TodayView + RootView) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 398 pass/1 skip (+3 AgentInboxTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — no ✕/card double-fire (Button wins hit-test), helper composes RecommendationQueue.pending + needsReview, RootView badge refactor makes it consistent with NotchSurface/HoverPanel (which already used the pending formula), pluralization + auto-hide correct
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-080209-bak-104-nudge/`
- **What landed:** `AgentInbox.waitingCount(recommendations:tasks:now:)`; TodayView dismissible "Agent has N things for you" nudge (tap→console, ✕ dismiss, auto-hide at 0); RootView waitingCount now shares the helper (snooze/ignore-aware).
- **Known non-blocking:** dismiss is session-scoped (won't reappear on new items same session); NotchSurface/HoverPanel still inline the same formula (future cleanup to route through AgentInbox).
- **Revert:** `git revert 8a19dbb5914d43fd53718066e1e33dc58ef36ff7`

## 2026-07-01 — MERGED · BAK-103 Today day-progress bar + Plan entry (PR #43)
- **Risk:** medium (Feature; DayPlanner helper + TodayView + RootView) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 395 pass/1 skip (+2 DayProgressTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — progress derivation correct (done in total, not pinned 100%), bar gated by total>0 (no NaN), onPlan default keeps preview safe, all 3 TodayView call sites compile, Theme tokens only
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-075733-bak-103-today/`
- **What landed:** `DayPlanner.dayProgress(_:day:)`; TodayView day-progress bar ("N of M done") + "✦ Plan with agent" header button (onPlan → RootView screen=.agent). Quick-add already existed (QuickCaptureField).
- **For Leon's eye:** progress bar fill + Plan button navigation.
- **Revert:** `git revert b5f45a52ecbbc3e76ac930e2e944d11289918ebd`

## 2026-07-01 — MERGED · BAK-102 board auto-collapse empty columns (PR #42)
- **Risk:** medium (Improvement; BoardView + PersonalBoard helper) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 393 pass/1 skip (+5 collapse-rule tests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — collapse predicate pure + all-branch tested, done "+N older" tail handled, no stuck/duplicate-key state, QuickColumnAdd not duplicated
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-075244-bak-102-column-polish/`
- **What landed:** `PersonalBoard.shouldCollapseEmpty(...)`; BoardView collapses empty columns to tap-to-expand strips (Everyone lens only, not Mine/Agent/review-focus); empty columns read "Drop here". Per-column "+ Add" was already QuickColumnAdd.
- **Known non-blocking:** a collapsed strip isn't a drop target (must click-to-expand first) — matches spec.
- **For Leon's eye:** strip appearance + click-to-expand.
- **Revert:** `git revert 1c73feb5f34defb357b78df4db17366e4ecc2785`

## 2026-07-01 — MERGED · BAK-101 board review-focus mode + caption (PR #41)
- **Risk:** medium (Feature; BoardView + PersonalBoard constant) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 388 pass/1 skip (+1 BoardFocusTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — toggle correct, columns pin to gateStages when focused, pill stays visible at count 0 (always an exit), count derived + owner/area-scoped, focus orthogonal to owner/area (no stuck state); removed 2 hardcoded hexes
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-074835-bak-101-review-focus/`
- **What landed:** header waiting pill → toggle button; review-focus collapses board to `PersonalBoard.gateStages` ([needsApproval, needsReview]); pill flips to "Exit review queue" (filled); focus-aware caption.
- **For Leon's eye:** collapse/restore + filled-pill state.
- **Revert:** `git revert 15c93d9297dedd4a82e18862c02be57aa5130318`

## 2026-07-01 — MERGED · BAK-100 board inline gate actions + reverse transitions (PR #40)
- **Risk:** medium (Feature; Logic helper + 2 views) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 387 pass/1 skip (+5 GateTransitionTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — state machine reused (not forked), gated/non-gated branch correct, labels exact, no tap double-fire (Button beats ancestor onTapGesture), delete is .nullify-safe (subtasks/delegation), reverse transitions stage-gated
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-074219-bak-100-gate-actions/`
- **What landed:** `PersonalBoard.approveTarget(for:)` (needsApproval→queued if gated else needsReview; needsReview→done); MustardBoardCard hover gate actions (✓ Approve & run / ✓ Approve / ✓ Accept + Deny/Discard-deletes); TaskDetailSheet Hold (queued→needsApproval) + Request changes (needsReview→queued).
- **For Leon's eye:** confirm hover reveal + that tapping the buttons doesn't also open the detail panel.
- **Revert:** `git revert 56b05ecbac91eeb96d966dc4799312244af3d06f`

## 2026-07-01 — MERGED · BAK-99 board card priority flag + Proposed pill + tags (PR #39)
- **Risk:** medium (Feature; Sources/ — additive model + view) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 382 pass/1 skip (+5 BoardCardMetaTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — enum reorder rawValue-stable (no migration), only exhaustive switch still exhaustive, no order-dependent consumers; flag hex matches handoff; isProposed + done-card gating correct
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-073543-bak-99-card-meta/`
- **What landed:** `TaskPriority.urgent` (reordered Low→Urgent, stable rawValues) + derived `MustardTask.isProposed` (agent+inbox); MustardBoardCard top-row priority flag (HIGH/URGENT) + ✦ Proposed pill + tags row (#tag, max 3), all Theme tokens. Create/edit Priority picker auto-gains Urgent via allCases.
- **For Leon's eye:** confirm HIGH/URGENT pill + Proposed pill + tags read well on a dense card.
- **Revert:** `git revert 85d9ec477de0938e7b329ecfcb66b2206ad5f922`

## 2026-07-01 — MERGED · BAK-98 design-token consolidation + confidence colour (PR #38)
- **Risk:** medium (Improvement; `Sources/` — Theme + 4 views + seed; no auth/trust/ClaudeRunner) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 377 pass/1 skip (+3 ThemeTests) · CI (self-hosted)
- **Review:** fresh-context APPROVE — render-identity verified hex-by-hex (every migrated token == original literal), drift fix matches README canonical, source-badge map reproduces handoff, ThemeTests pin thresholds
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-071051-bak-98-tokens/`
- **What landed:** `Theme` is now the canonical handoff token home (surfaces, agent tints, done/review, warn, status, confidence, priority, area dots); single `Theme.confidenceColor` (≥0.7/≥0.5) + `confidenceTier`; centralised `Theme.sourceBadge`. MustardBoardCard + BoardView.ColumnStyle inline hex → tokens (renders identically). Drift fix: RecommendationDetailView + AgentConsoleView dropped their ≥0.4 amber cutoff (0.40–0.49 now red). Seed Admin dot green #3E8E7E.
- **Behaviour change:** confidence 0.40–0.49 shifts amber→red in rec-detail + console (intended). Preview-only: a seeded gmail-source card now shows the Gmail badge (was KB grey) — toward spec.
- **Deferred:** exact handoff per-list dot colours under one group header need a per-list `TaskList.colorHex` (model change) — documented in the PRD, not done here.
- **For Leon's eye:** confirm board/console look unchanged + the gmail preview card badge reads right.
- **Revert:** `git revert 501e8d6284faad64693b9acb406f822d1ca6784e`

## 2026-07-01 — MERGED · BAK-97 vendor 2026 redesign handoff + PRD (PR #37)
- **Risk:** low (docs-only; `docs/design/redesign-2026/**` + run artifacts; no Sources/Package/config) · **Deep-review:** n/a (low auto-merges after fresh-context review)
- **Checks:** swift build clean · swift test 366 pass/1 skip (baseline; no behaviour changed) · CI (self-hosted)
- **Review:** fresh-context APPROVE; one non-blocking nit (PRD threshold recommendation mislabelled the ≥0.5 set as "desktop code") fixed before merge
- **Outward actions:** none
- **Run:** `.agent-loop/runs/20260701-061603-bak-97-vendor-handoff/`
- **What landed:** vendored desktop+mobile prototypes + handoff README into `docs/design/redesign-2026/` (excludes prototype runtime support.js/ios-frame.jsx) and a `PRD.md` mapping the handoff to the BAK-97..119 task graph; documents two parity discrepancies (confidence thresholds; Admin dot colour) for BAK-98.
- **Kickoff context:** first slice of the 2026 redesign. Most of the desktop is already shipped — remaining work is the desktop delta (BAK-98..107, parity audits 111/112/117/118) + the iOS companion (foundation BAK-108, blocked on Apple Dev entitlements → shell 110 → screens 113/114/115/116/119).
- **Revert:** `git revert 0aa29e7fbd7b161e31dcf49dfd7345bbdc07a3e7`

## 2026-06-30 — MERGED · BAK-84 quarantine undecodable agent result files (PR #36)
- **Risk:** medium (Improvement; Logic + BridgeIO + a one-line `ingestAgentResults` call) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift test 366 pass/1 skip (+5 tests) · swift build clean · CI (self-hosted) green 43s
- **Review:** fresh-context no blockers; keep-criterion parity confirmed exact; Part-1 obsolescence independently verified; rerun-idempotency test folded in (45ba930)
- **Outward actions:** none · quarantine relocates a local file Mustard already ignores
- **Run:** `.agent-loop/runs/20260630-203248-bak84-bridge-routing/`
- **What landed (Part 2):** `BridgeIO.quarantineUndecodableResults` moves undecodable/empty-uid `results/*.json` → `results/quarantine/` (same keep-criterion as readResults); `ingestAgentResults` calls it each run after archiving the good ones; `BridgeFolders.resultsQuarantine`.
- **Part 1 (route via AreaRouter) — OBSOLETE:** BAK-87 already reworked routing (loop uses each SourceConfig's `workingDirectory` + `AreaMapping`, never `defaultAreaMap`); `AreaRouter` is dead. Documented + stale comment refreshed; dead-AreaRouter removal filed as **BAK-96**.
- **Process note:** built in an isolated git worktree off `origin/main` (per the BAK-90 concurrency lesson).
- **Revert:** `git revert f911b85dfdf8ade62f3e452930bf4af7c5d155cb`

## 2026-06-30 — MERGED · BAK-91 capture + surface referenced Shortcut/Jira link (PR #35)
- **Risk:** medium (Feature; new Logic helper + a 2-line `materializeTask` change + a View; the AgentService touch carries no dispatch/gating logic) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift test 361 pass/1 skip (+9 tests) · swift build clean · CI (self-hosted) green 44s
- **Review:** fresh-context no blockers; its one finding (host-substring label false positives) fixed in commit a07e461 + regression tests
- **Outward actions:** none · reads/parses text + stamps fields on a new inbox task
- **Run:** `.agent-loop/runs/20260630-201835-bak91-task-links/`
- **What landed:** pure `TaskLinkExtractor` (NSDataDetector → Shortcut/Jira/host labels, host-boundary match, dedupe); `materializeTask` carries `rec.sourceURL` + `task.links`; `TaskDetailSheet` Links section (show/open/remove/add).
- **Process note:** built in an ISOLATED git worktree off `origin/main` (per the BAK-90 concurrency lesson) — no shared-HEAD collision this time.
- **Leon — visual confirm pending:** Links section shows/opens carried links; manual add works (UI build-verified only).
- **Revert:** `git revert 52a89e7669273c87f581f37dc1b6f3b7fc5e24fb`

## 2026-06-30 — MERGED · BAK-90 require a client area before agent hand-off (PR #33)
- **Risk:** high (escalated — touches `AgentService.delegate`, the agent hand-off control path) · **Deep-review:** PASS (3/3 — correctness + security/risk + spec-faithfulness, all clear)
- **Checks:** swift test 352 pass/1 skip (+4 tests) · swift build clean · CI (self-hosted) green 47s
- **Review:** fresh-context NON-BLOCKING (mergeable); panel 3/3 clear
- **Outward actions:** none · the change BLOCKS a hand-off; performs no send/deploy/delete
- **Run:** `.agent-loop/runs/20260630-195959-bak90-require-area/` (artifacts stranded on the `leon/bak-82` branch — see note below)
- **What landed:** pure `PersonalBoard.canHandOffToAgent` (area required); `AgentService.delegate` guards on it (chokepoint for all 4 "Ask agent" buttons) + `lastHint`/`clearHint`; BoardView drop-handler guard + amber hint banner.
- **Follow-up filed:** BAK-95 — TaskDetailSheet Stage/Assignee pickers still bypass the gate (benign; export filters by area regardless).
- **⚠️ Concurrency note:** this run collided with a parallel dev-loop session building BAK-82 in the SAME working tree — that session checked out `leon/bak-82` off this branch's tip, so the BAK-90 run-artifacts commit (5cdc3fe) and this entry's source landed via an isolated worktree. PR #33 itself was clean (single BAK-90 commit). Recommend per-session git worktrees/clones to prevent shared-HEAD stomping.
- **Revert:** `git revert 7d4282d1ee1915824818ac0bedb189ddd6e3dba0`

## 2026-06-30 — MERGED · BAK-89 settable task actionType + export guard (PR #32)
- **Risk:** medium (Feature; Logic + Views; no high path, no AgentService change) · **Deep-review:** n/a (medium auto-merges after fresh-context review)
- **Checks:** swift test 348 pass/1 skip (+3 tests) · swift build clean · CI (self-hosted) green 42s
- **Review:** fresh-context APPROVE, no blockers (one follow-up test folded in)
- **Outward actions:** none · the change makes export STRICTER + adds UI
- **Run:** `.agent-loop/runs/20260630-195145-bak89-actiontype/`
- **What landed:** `BridgeExport.plan` skips a `.queued` task with no actionType (would emit an empty-action execute order; forAgent/prep exempt); `TaskDetailSheet` Action picker; `MustardBoardCard` amber "Needs an action type" pill.
- **Leon — visual confirm pending:** Action picker persists; queued card flips amber→"Queued to run" once an action is set (UI build-verified only).
- **Revert:** `git revert da775334b011147adca8cd06dd6e49b5e049ee40`

## 2026-06-30 — MERGED · BAK-92 bridge double-execution race fix (PR #31)
- **Risk:** high (escalated — agent work-dispatch correctness path; no high path literally matched) · **Deep-review:** PASS (3/3 — correctness + security/risk + spec-faithfulness, all clear, no fix round)
- **Checks:** swift test 345 pass/1 skip (+6 tests) · swift build clean · CI (self-hosted) green 42s
- **Outward actions:** none · the diff is pure logic + a non-mutating dir read; it makes dispatch strictly *more* conservative
- **Run:** `.agent-loop/runs/20260630-191727-bak92-bridge-double-exec/`
- **Root cause:** between the worker archiving a consumed outbox order + writing a result and Mustard's next ingest tick, the task stays `.queued`/`.forAgent` with no live outbox file → `BridgeExport.plan` re-issued the order → a worker on the duplicate executes twice (e.g. a second Gmail draft / Shortcut story).
- **Fix:** `plan` gains a `liveResultUIDs` guard — suppress a re-write when a LIVE `results/<uid>.json` exists (NOT `results/done/`, so the `failed`-retry path still re-issues). New `BridgeIO.liveResultUIDs` (non-recursive). Loop ordering (export→ingest) documented as load-bearing.
- **Follow-ups (non-blocking, panel-raised):** fail-open hardening of `liveResultUIDs` (distinguish absent dir vs listing error); worker-side idempotency backstop (Phase 3); true exactly-once via atomic outbox claim.
- **Revert:** `git revert 6ca9bd05c647f4089d59125bf12b76703dc926f3`

## 2026-06-29 — MERGED · BAK-87 project→area routing fix (PR #29)
- **Risk:** high (AgentService) · **Deep-review:** PASS (2-lens — correctness + security/scope, both clear; small focused fix)
- **Checks:** swift test 339 pass/1 skip · swift build clean
- **Root cause:** `project` stored as folder name ("DL-Knowledge-Base") but area maps code-keyed ("DL") → bridge export was DORMANT in real config + promote stamped no area → triage-approved recs never reached the outbox.
- **Fix:** `AreaMapping.areaName(forProject:)` (folder-name + code → area); bridge loop uses it; promote/materializeTask stamp the task's area (find-or-create). `AreaRouter` now dead code.
- **Revert:** `git revert 12540b9739eabde787921fb07b867c4b93df94c7`

## 2026-06-29 — MERGED · BAK-83 Agent Bridge Phase 2 (PR #27)
- **Risk:** high (touches AgentService) · **Deep-review:** PASS (3/3 clear, no fix round)
- **Checks:** swift test 334 pass/1 skip · swift build clean · CI (self-hosted)
- **Outward actions:** none · bridge is file I/O only (no execution/send); staging-only
- **Run:** `.agent-loop/runs/20260629-agent-bridge-phase2/`
- **What landed:** AgentWorkOrder/AgentResult schemas, pure BridgeExport/BridgeIngest, FileBridgeIO, AgentService export+ingest on the 10-min loop, file-contract doc
- **Follow-ups:** route via AreaRouter (vs defaultAreaMap); archive undecodable result files; (BAK-82 meeting titles, separate)
- **Deferred:** Phase 3 — the connected-session worker that drains outbox, runs dl-create-shortcut-story, writes results
- **Revert:** `git revert fe3b5b1b08e02475d9f23bc9215caca82ecc1e99`

## 2026-06-29 — MERGED · BAK-73 Agent Task Board Phase 1 (PR #26)
- **Risk:** high (agent core — AgentService rewired) · **Deep-review:** PASS (3/3 clear after 1 fix round)
- **Checks:** swift test 315 pass/1 skip · swift build clean · CI (self-hosted)
- **Outward actions:** none · Phase 1 is staging-only (no executor drains `.queued`)
- **Run:** `.agent-loop/runs/20260629-board-phase1/`
- **What landed:** `TaskStage` model + migration, owner-segmented board UI, rec→board promotion, OutputCard/DelegationPhase retired, ADR-0010
- **Follow-ups:** BAK-82 (meeting task titles); VersionedSchema hardening; minor board UI tweaks (Leon)
- **Deferred:** Phase 2 (vault-file bridge) + Phase 3 (connected-session worker) — each gets its own spec
- **Revert:** `git revert 9ad0f2896d5a32bcc0bb8412d74bb1201081c454`

## 2026-06-29 — MERGED · BAK-45 Live Google Calendar connect (PR #25)
- **Risk:** high (OAuth/auth + Keychain) · **Deep-review:** PASS (3/3 clear after 1 fix round)
- **Checks:** swift test 323 pass/1 skip · swift build clean · CI (self-hosted) green
- **Outward actions:** none · client secret user-entered, Keychain-only
- **Run:** `.agent-loop/runs/20260629-103052-bak45-gcal-connect/`
- **Remaining:** manual live connect test (Task 10, Leon) — paste Desktop client id+secret in Settings → Connect
- **Follow-ups:** BAK-71 (Theme error token, test stub dedup, window edge)
- **Revert:** `git revert e7675bd7da0536f1dcc263ebe19eb8e87c6c8b65`
