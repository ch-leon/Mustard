# Mustard — Rich Triage Cards (Plan 6 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Bring the old triage tool's review/approval richness into Mustard's
Recommendations queue: source provenance, confidence + reasoning, an editable
draft reviewed *before* execution, re-bucket (change action), and the full
outcome set (Approve · Edit · Change action · Comment · Schedule · Snooze ·
I'll do it · Reject). Synthesize confidence × trust for auto-run.

**Scope now (vault source):** confidence, reasoning, editable draft, comment,
snooze, re-bucket chips, outcome verbs — all real against the vault. Source
provenance fields (source/context/url) and draft *types* carried in the model
from day one but only light up fully when email/Slack sources arrive.

**Model (`Recommendation` additions):** `confidence: Double = 0.5`,
`reasoning = ""`, `draft = ""`, `source = "vault"`, `sourceContext = ""`,
`sourceURL: String?`, `comment = ""`, `snoozedUntil: Date?`. `proposedActionType`
stays the action token.

**`RecommendationAction` enum** (rawValues): `draft_email`(gated) · `draft_slack`(gated)
· `create_task` · `vault_note` (default) · `ticket_write`(gated) · `fyi` · `ignore`.
`TrustPolicy.gatedActionTypes` derives from `.isGated`.

**confidence × trust:** `shouldAutoApprove(actionType:trust:confidence:)` also
requires `confidence ≥ autoConfidenceThreshold (0.7)`.

**Sweep:** prompt asks for `[{title, body, action_type, confidence, reasoning, draft}]`;
parser reads them (confidence clamped 0–1, defaults when missing).

**UI:** `RecommendationRow` becomes expand-to-review. Collapsed: source · title ·
action chip + confidence meter · reasoning (1 line) · Approve/Deny/expand.
Expanded: re-bucket chips, editable draft (`TextEditor` bound to `rec.draft`),
Comment field, and outcomes Approve · Edit · Comment · Schedule · Snooze · I'll do
it · Reject. Pending filter excludes snoozed (`snoozedUntil > now`).

**Tasks (TDD where logic):** 1) `RecommendationAction` + TrustPolicy gated-from-enum
+ confidence threshold (+tests). 2) sweep prompt/parser confidence/reasoning/draft
(+tests). 3) `Recommendation` model fields. 4) AgentService sweep mapping + applyTrust
confidence + comment/snooze methods (+tests). 5) Rebuild `RecommendationRow` review
drawer + console snooze filter. Build/relaunch/commit.

**Done when:** tests green; a swept recommendation shows confidence + reasoning +
editable draft; low-confidence never auto-runs even when Trusted; Comment/Snooze work.
