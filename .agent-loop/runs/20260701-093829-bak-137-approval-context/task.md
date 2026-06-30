# BAK-137 — Task detail read-mode approval context

**Run:** 20260701-093829 · **Milestone:** Redesign · Desktop delta · **Risk:** medium (TaskDetailSheet view)

Surfaced the prototype's approval-panel info as a read-only `agentContext` section in the
sheet (shown when the task carries agent context): stage badge, 🔒 gated notice,
confidence (numeric + bars via Theme.confidenceColor), WHY (delegation.reasoning), DRAFT
(delegation.draft). Decision: no separate read/edit mode-toggle — the sheet shows the
context AND stays editable, avoiding an IA fork; this delivers the approval-view content.
The green agent-output block stays N-A (review is console/board per ADR-0010).
