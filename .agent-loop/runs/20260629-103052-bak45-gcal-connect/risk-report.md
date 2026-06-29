# Risk Report

Declared task risk: high (issue BAK-45 priority High; feature involves auth)
Touched-path risk: **high**
Highest risk: **high**
Needs deep-review panel: **yes**
Irreversible outward actions: **none**

## Evidence

Task labels: (none on issue) — risk inferred from intent (OAuth/auth feature).

Changed files (planned):
- Sources/MustardKit/Calendar/CalendarTypes.swift
- Sources/MustardKit/Calendar/GoogleOAuth.swift (modify)
- Sources/MustardKit/Calendar/LoopbackRedirectServer.swift
- Sources/MustardKit/Calendar/GoogleTokenClient.swift
- Sources/MustardKit/Calendar/GoogleEventsClient.swift
- Sources/MustardKit/Calendar/TokenStore.swift
- Sources/MustardKit/Calendar/CalendarSync.swift
- Sources/MustardKit/Calendar/GoogleAuthSession.swift
- Sources/MustardKit/Calendar/GoogleCalendarService.swift
- Sources/MustardKit/Views/SourceSettingsView.swift (modify)
- Sources/Mustard/MustardApp.swift (modify)
- Tests/MustardTests/* (new test files)

Policy matches (`.agent-loop/risk.yml` path_risk.high, case-insensitive substring):
- `auth` → matches `GoogleAuthSession.swift`, `GoogleOAuth.swift`
- `oauth` → matches `GoogleOAuth.swift`
- (medium) `Sources/` → matches all source files

`outward_actions` check: none performed. No deploy, no email/Slack send, no remote-data
deletion, no secret rotation, no force push. The OAuth client secret is **user-entered
at runtime** and stored **only in the macOS Keychain** — never written to the repo.

## Decision

High risk. Auto-merge is gated on the `deep-review` adversarial panel passing
(`risk_classes.high.auto_merge: after_deep_review`). No irreversible outward action, so
no human yes/no gate is required for the merge itself — only the panel.
