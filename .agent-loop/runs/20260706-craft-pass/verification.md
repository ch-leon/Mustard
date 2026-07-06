# Verification — Craft pass (Phases 0–2, spec 2026-07-06)

Environment note: this run was driven from a Linux container with **no Swift
toolchain** (SwiftUI/AppKit cannot compile on Linux), so the required checks
(`swift test`, `swift build`) ran exclusively on the **macOS CI runner** attached
to PR #78 ("Build & test (macOS)"). Every slice below links its run.

| Slice | Commits | CI run | Result |
|---|---|---|---|
| Phase 0 tokens + Phase 1 surface polish (+ plan docs) | `714921c`..`b58d71f` | [28784667633](https://github.com/ch-leon/Mustard/actions/runs/28784667633) | ✅ build + tests green |
| Milestone 2a — live editor (NoteDecoration, MarkdownTextView, header, linked-references card; 40 new tests) | `3af63c2`..`e31d702` | [28785818452](https://github.com/ch-leon/Mustard/actions/runs/28785818452) | ❌ 4 compile errors (AppKit implicit-member inference) |
| 2a fix — explicit AppKit types | `352b613` | [28785946214](https://github.com/ch-leon/Mustard/actions/runs/28785946214) | ✅ build + full suite green (incl. all 2a tests) |
| Milestone 2b — slash menu, block reorder, gutter, subpage cards (21+ new tests) | `f97dcbc`..`7ce2d67` | [28787344892](https://github.com/ch-leon/Mustard/actions/runs/28787344892) | ❌ compiled; 7 test failures (CRLF grapheme-cluster bugs) |
| 2b fix — unicodeScalars terminator check + isNewline test helper | `89a662b` | [28787673938](https://github.com/ch-leon/Mustard/actions/runs/28787673938) | ✅ build + full suite green — **647 tests, 1 pre-existing skip, 0 failures** |
| Review remediation — Task 11 docs, risk→High, review artifacts | `8732971` | docs-only | ✅ (same code as green run) |
| Deep-review fixes — /Sub-page dangling link (undo symmetry) + undo-stack clear on note switch | `e274e49` + HEAD | final run on HEAD | see PR checks — must be green before merge |

Views are verified per CLAUDE.md convention by build + Leon's eye — the agent
does not claim visual correctness. Eye checklist for Leon is in the Phase 2 plan
(caret stability, undo purity, ⌘S/dirty dot, save-on-switch, wikilink click +
create-from-dangling, frontmatter-as-quiet-block, large-note latency, header/card
look).
