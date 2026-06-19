# Architecture Decision Records

Each ADR captures one significant decision: its context, the call, and the
consequences. Supersede rather than edit when a decision changes.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-swiftdata-cloudkit-not-server.md) | SwiftData + CloudKit, no hosted backend | Accepted |
| [0002](0002-native-swiftui-not-web-wrapper.md) | Native SwiftUI, not an Electron/Tauri web wrapper | Accepted |
| [0003](0003-agent-via-claude-subscription.md) | Agent runs via the `claude` CLI subscription, not the API | Accepted |
| [0004](0004-spm-now-xcode-for-cloudkit.md) | Ship as a Swift Package now; Xcode project when CloudKit/iOS land | Accepted |
| [0005](0005-things3-calm-design.md) | "Things 3 calm" as the fixed design language | Accepted |
| [0006](0006-confidence-times-trust-gating.md) | Auto-run gated by confidence × trust, with always-gated actions | Accepted |
| [0007](0007-cloud-scout-for-email-discovery.md) | Email discovery via a cloud-routine scout (vault-as-git-transport) | Superseded by 0008 |
| [0008](0008-local-only-email-scout.md) | Email scout is local-only — no cloud routine, no git | Accepted |
| [0009](0009-curated-kb.md) | Curated KB: store only Kept items; retire the email→KB firehose | Accepted |
