# Mustard — Notch Surface (Plan 3 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Spec §6a first slice: an ambient notch surface. Idle = a thin black notch-hugging strip rotating through current focus → agent-waiting count. Hover = expands below the notch into a dark panel with the focus task, the top pending recommendations (inline Approve/Deny), and quick capture.

**Architecture:** `NotchController` owns a borderless, non-activating `NSPanel` at status-bar level, anchored top-center over the physical notch (width from `NSScreen` auxiliary areas; graceful fallback width on non-notched displays). Idle/expanded are two frame sizes animated with `setFrame(animate:)`; SwiftUI content reports hover via callback. The notch surface is intentionally **dark** (it extends the physical hardware) even though the app theme is light — text white, rounded bottom corners, seamless black.

**Pure logic tested:** `NotchTicker.idleItems(focusTitle:waitingCount:)` (the rotation list). UI verified by build + eyes.

**Tasks:**
1. `NotchTicker` pure rotation provider + tests. Commit.
2. `NotchSurface.swift`: `NotchController` (panel setup, notch geometry, expand/collapse frames) + `NotchView` (idle strip with `TimelineView` rotation; expanded panel: focus row, ≤3 pending recommendations with Approve/Deny via `AgentService`, `QuickCaptureField` reuse, waiting badge). Commit.
3. Wire into `MustardApp`: show on launch, "Toggle Notch" ⌘⇧N command. Build, relaunch, commit.

**Done when:** tests green, app launches with the notch strip visible on the built-in display, hover expands it, Approve in the notch executes and the card lands in the Review queue.

**2026-07-02 update:** the hover-expanded panel described above (focus row +
3 meetings + inline recommendation Approve/Deny) was replaced by the triage
summary card + full today-agenda redesign in
`docs/superpowers/plans/2026-07-02-notch-expanded-redesign.md`. Screen
selection also changed to prefer an external monitor over the built-in
notch display when one is connected.
