# Risk report — Notes Phase A (BAK-145)

**Highest applicable risk class: MEDIUM** → auto-merge after fresh-context review
(`.agent-loop/risk.yml`: medium.auto_merge = true).

## Labels
- Linear issues carry `Feature` → task_label_risk **medium**.

## Touched paths (git diff f88a53a..HEAD --stat)
- `Sources/MustardKit/**` (new Logic/Models/Agent/Views files + NotesView/RootView/
  CommandBar/MustardContainer/PreviewData edits), `Sources/Mustard/MustardApp.swift`
  → path_risk **medium** ("Sources/").
- `Tests/**`, `docs/**`, `CLAUDE.md`, `.agent-loop/runs/**` → low.
- **No high-risk paths touched:** no diff hunk in ClaudeRunner, TrustPolicy,
  RecommendationAction, GoogleOAuth/auth/token files, `.github/workflows/`, or
  anything matching the high patterns. `FileVaultIO` gained a NoteVaultIO extension;
  the meeting-sync surface (`MeetingVaultIO`, `meetingNotePaths`) is byte-unchanged.

## Irreversible outward actions
- **None.** No release/tag, no remote deletion beyond the merged PR's own branch
  (policy-sanctioned via `gh pr merge --delete-branch`), no secret rotation, no
  force push. The feature writes only (a) `.md` files inside the user-configured
  project working directories (editor save = snapshot-then-write to
  `hub/.snapshots/` first; new notes into `<project>/notes/`), and (b) the local
  SwiftData store (`NoteIndexEntry` mirror rows).

## Blast radius notes
- Reindex is read-only over the vault (enumerate + read); wholesale rebuild is
  scoped per project by predicate — cannot touch other projects' rows.
- Editor saves are guarded by a prior-content snapshot (spec addendum #5), so no
  silent destruction path; failed writes leave visible dirty state.
- The 60s-loop addition is pure local FS work throttled to 300s per project; no
  claude invocations added (no subscription-cost change).
