# Risk Report — BAK-133
**MEDIUM** → auto-merge after fresh-context review.
- Label: Improvement. Paths: SettingsView.swift (new view) + RootView.swift (enum case, sidebar, screen switch, dock condition). NOT TrustPolicy.swift.
- Trust control here binds the same @AppStorage("trustLevel") + agent.applyTrust as the console (no gating-logic change). No schema/outward.
