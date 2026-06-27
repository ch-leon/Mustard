# Agent Loop Done Criteria

A task is done only when all applicable items are complete.

- [ ] The requested vertical slice is implemented.
- [ ] The implementation stays inside the task scope.
- [ ] Required checks in `.agent-loop/checks.yml` passed.
- [ ] Verification output is summarized in `.agent-loop/runs/<run-id>/verification.md`.
- [ ] Fresh-context standards review has no blocking findings.
- [ ] Fresh-context spec review has no blocking findings.
- [ ] Risk report identifies the highest risk class from labels and paths.
- [ ] High-risk work passed the adversarial `deep-review` panel.
- [ ] Any irreversible outward action was explicitly confirmed by Leon.
- [ ] PR body and digest entry record summary, checks, risk, review result, and known limitations.
