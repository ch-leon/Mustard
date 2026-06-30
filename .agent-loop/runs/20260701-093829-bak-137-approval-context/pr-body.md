## BAK-137 — Task detail read-mode approval context

Surface the prototype's approval-panel info as a read-only section in the detail sheet (when the task carries agent context): stage badge, 🔒 gated notice, confidence (numeric + bars), WHY, and the proposed DRAFT — from `task.confidence` / `task.delegation`.

Decision: no separate read/edit mode-toggle — the sheet shows context AND stays editable (avoids an IA fork). Green agent-output block stays N-A (review is console/board per ADR-0010).

swift build clean · swift test 419 pass/1 skip. Risk: medium (view).
