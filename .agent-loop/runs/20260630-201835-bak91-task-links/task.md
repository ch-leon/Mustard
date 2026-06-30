# BAK-91 — create_task tasks: capture + surface the referenced Shortcut/Jira link

**Issue:** https://linear.app/bakinglions/issue/BAK-91 · **Label:** Feature
**Branch:** `leon/bak-91-capture-shortcut-jira-link` (isolated worktree — see note)

## Problem
Approving a `create_task` rec that references an existing Shortcut story / Jira issue
landed an inbox task with no link — nowhere to see/open the referenced item.
`MustardTask.links` existed but `materializeTask` never populated it.

## Fix
1. **Pure extractor (TDD):** `TaskLinkExtractor.referencedLinks(in: [String?])` — uses
   `NSDataDetector(.link)` to pull http(s) URLs from the rec's text fields, labels them
   Shortcut / Jira / host, dedupes (first occurrence wins).
2. **`materializeTask`** now carries `rec.sourceURL` → `task.sourceURL` and populates
   `task.links` from the extractor over `[sourceURL, draft, body, sourceContext,
   originalSource]`.
3. **UI (build+eye):** `TaskDetailSheet` gains a "Links" section — show + open each link,
   remove, and add one manually (http/https, deduped via `TaskLinkExtractor.label`).

### Files
- `Sources/MustardKit/Logic/TaskLinkExtractor.swift` — new pure helper.
- `Sources/MustardKit/Agent/AgentService.swift` — `materializeTask` carries links + sourceURL.
- `Sources/MustardKit/Views/TaskDetailSheet.swift` — Links section + manual add.
- Tests: `TaskLinkExtractorTests` (6) + `AgentTests.test_approve_createTask_capturesReferencedLink` (1).

## Acceptance criteria
- [x] materializeTask carries any referenced URL into `task.links`.
- [x] A UI place to show + open the link (TaskDetailSheet Links section).
- [x] Add one manually.

## Notes
- Done in an **isolated git worktree** off `origin/main` to avoid the shared-checkout
  collision with the parallel BAK-82 dev-loop session (see digest BAK-90 entry).
- UI is build-verified only (CLAUDE.md). Leon confirms visually.
