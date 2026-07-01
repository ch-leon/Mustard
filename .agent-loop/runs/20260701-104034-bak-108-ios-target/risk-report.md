# Risk Report — BAK-108
**HIGH** (structural: new build tooling / iOS target; ADR-0004 migration boundary) → deep-review panel before merge.
- Touched: project.yml (new), Sources/MustardMobile/ (new stub), build-ios.sh (new), Sources/MustardKit/Agent/ClaudeRunner.swift (#if os(macOS) guard + iOS stub), .gitignore, docs/adr/0004 note.
- **Blast radius is bounded:** Package.swift UNCHANGED → swift build/test/CI/build-app.sh unaffected (verified macOS 419 pass). The xcodeproj is additive + git-ignored.
- ClaudeRunner change: macOS behaviour byte-for-byte identical (guarded region unchanged); iOS gets a no-op stub. Not a gating/trust path.
- No Apple account, no entitlements, no CloudKit, no outward actions.
