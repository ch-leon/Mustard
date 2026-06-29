# Dev-loop Digest

Append-only ledger of merges and holds. Each entry carries a ready `git revert` line.

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
