# Spec — Recommendation source classification + console fixes (2026-07-08)

Three agent-console bugs from Leon's feedback review. Source classification confuses a
Jira/Shortcut *content mention* for the actual *source*.

## 1. Label-driven source classification
**Bug:** a Gmail human reply that mentions a Jira ticket key (e.g. "DLA-5598") is
reclassified to `.jira` by `SourceClassifier` because the ticket-key regex fires on
`sourceContext`.

**Fix:** Gmail labels are ground truth (Jira/Shortcut robots auto-filter into a label;
a human reply does not). Thread the thread's Gmail labels through the pipeline:
- `SourceProposal` gains `labels: [String]` (default `[]`, decode-tolerant for legacy recs).
- `IngestNormalizer` passes `p.labels` into the classifier; `reclassified(...)` preserves them.
- `SourceClassifier.logicalSource(transport:sourceContext:labels:)`:
  - non-gmail transport → unchanged.
  - **labels present** → decide by label (`Jira`/`Jira Updates` → `.jira`,
    `Shortcut Notifications` → `.shortcut`), else `.gmail`. The content-regex is NOT
    consulted — this is what fixes the bug.
  - **labels empty** (legacy) → old provenance-text heuristics (prefix + ticket-key regex).
- Scout prompt emits `labels` for each rec.

## 2. Shortcut rec "Open" opens Jira
**Bug:** a Shortcut-sourced rec's `sourceURL` is a synthesized Jira `browse/DLA-xxxx` URL.
**Fix (Mac guard):** `SourceLink.init?` rejects (`nil`) when `source == shortcut` but the
URL host is jira/atlassian. Scout prompt: Shortcut items must carry the real
`app.shortcut.com/story/…` link.

## 3. Comment field carries over between recs
**Bug:** `RecommendationDetailView` `@State commenting/commentText` survive selection
changes (view instance reused).
**Fix:** `.id(selected.persistentModelID)` on the detail view in `AgentConsoleView`.

## Tests
- `SourceClassifierTests`: label-decisive jira/shortcut, labels-present-but-none →
  gmail even with a ticket key in context (the bug case), non-gmail passthrough,
  legacy no-labels fallback unchanged.
- `SourceLinkTests`: shortcut+jira-host → nil; shortcut+shortcut-host → ok;
  jira+jira-host still ok (guard scoped to shortcut).
- #3 is a view change — verified by `swift build` + Leon's eye.
