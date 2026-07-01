## BAK-133 — Standalone Settings screen

Adds a dedicated **Settings** screen (sidebar **⚙**, pinned bottom) hosting **Sources** (`SourceSettingsView`) + a **Trust** section (segmented control + blurb + gated footer note).

Additive per CLAUDE.md ("trust surfaced in the Agent header pill **and** Settings") — the console's trust control stays; both bind the same `@AppStorage("trustLevel")` so they sync. No IA thrash.

- `MustardScreen.settings` (excluded from `.primary`); sidebar ⚙; screen switch renders `SettingsView`; co-pilot dock now hidden on Settings too.

swift build clean · swift test 419 pass/1 skip. Risk: medium (new view + RootView).
