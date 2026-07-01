# Risk Report — BAK-110
**MEDIUM** → auto-merge after fresh-context review.
- New iOS-only UI under Sources/MustardMobile/ (built by the XcodeGen target). Package.swift/macOS untouched (no shared-file edits) → swift test/build unaffected (419 pass).
- No high paths, no schema, no outward actions. AgentService on iOS uses the Mac-only no-op ClaudeRunner stub.
