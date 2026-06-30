## BAK-91 — create_task tasks: capture + surface the referenced Shortcut/Jira link

Approving a `create_task` rec that referenced an existing Shortcut story / Jira issue landed an inbox task with **no link** — nowhere to see or open the referenced item. `MustardTask.links` existed but `materializeTask` never populated it.

### Changes
- **`TaskLinkExtractor`** (new, pure) — `referencedLinks(in: [String?])` uses `NSDataDetector` to pull http(s) URLs from a rec's text, labels them Shortcut / Jira / host (on host **boundaries**, not substrings), dedupes (first occurrence wins).
- **`AgentService.materializeTask`** — carries `rec.sourceURL` → `task.sourceURL` and populates `task.links` from `[sourceURL, draft, body, sourceContext, originalSource]`.
- **`TaskDetailSheet`** — a "Links" section: show + open each link, remove (×), and add one manually (http/https, deduped).

### Tests (TDD, red→green)
- `TaskLinkExtractorTests` (8): Shortcut/Jira/host labeling, dedupe across texts, first-occurrence order, ignores non-http/empty, **look-alike hosts not mislabelled**, self-hosted `jira.<co>.com`.
- `AgentTests.test_approve_createTask_capturesReferencedLink`: approving a create_task rec with a Shortcut URL lands a task with `links` + `sourceURL` carried.

### Checks
- `swift test` → 361 pass / 1 skip (+9 tests)
- `swift build` → clean (executable links)

### Risk
Medium (`Feature`; new Logic helper + a 2-line `materializeTask` change + a View). The AgentService touch is confined to `materializeTask` and is purely additive provenance-stamping — no dispatch/gating/execution logic — so not escalated to high. No irreversible outward action.

### Review
Fresh-context review: **no blockers**. Its one actionable finding (host-substring label false positives) is fixed in commit `a07e461` with boundary matching + regression tests.

### Note for Leon (UI — build-verified only)
The Links section can't be screenshotted in-session (CLAUDE.md). Please eyeball: a create_task task carrying a Shortcut/Jira link shows it under "Links" in the detail sheet; clicking opens it; × removes; pasting a URL + Enter adds it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
