# BAK-133 — Standalone Settings screen

**Run:** 20260701-101425 · **Milestone:** Redesign · Desktop delta · **Risk:** medium (new view + RootView)

**Decision (per "keep charging" + CLAUDE.md "trust surfaced in the Agent header pill AND
Settings"):** additive — added a dedicated Settings screen without removing the console's
trust control (both bind @AppStorage("trustLevel"), stay in sync). No IA thrash.

- New `SettingsView`: "Settings" header + `SourceSettingsView` (Sources) + a TRUST section
  (segmented control + blurb + gated footer note).
- `MustardScreen.settings` case (+ gearshape icon), excluded from `.primary`.
- Sidebar: **⚙ Settings** pinned at the bottom (per handoff).
- Screen switch renders `SettingsView`; the co-pilot dock now hides on `.settings` too
  (handoff: dock shown everywhere except Agent and Settings).

## Deferred within scope
Per-source "● Connected" indicators on every source row (BAK-133 also mentioned this) —
Google Calendar already shows Connected; project rows use an enable toggle. Left as-is;
not worth a model change. The standalone-screen ask is delivered.
