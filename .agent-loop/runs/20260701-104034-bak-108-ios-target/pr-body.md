## BAK-108 — iOS app target via XcodeGen (ADR-0004)

Stands up the iOS companion foundation, additively — the moment the mobile screens (BAK-110+) can be built for the Simulator with **no Apple account**.

### Approach (XcodeGen, simulator-first)
- Committed `project.yml` → generates `MustardMobile.xcodeproj` (git-ignored) via `./build-ios.sh`.
- The iOS app compiles the platform-agnostic core (Models + Logic + Agent + MustardContainer), **excluding `Views/`** (AppKit).
- `ClaudeRunner`'s `Process` path is `#if os(macOS)`-guarded with an iOS stub (agent runs on the Mac only, ADR-0003).
- **macOS untouched** — Package.swift/`swift build`/`swift test`/`build-app.sh` unchanged.
- Stub `MobileRootView` proves the core links; bottom-tab shell + screens are BAK-110+.

### Checks
- iOS: `xcodebuild -destination 'iOS Simulator'` → **BUILD SUCCEEDED**.
- macOS: `swift build` clean · `swift test` 419 pass/1 skip.

### Risk
HIGH (structural / new build tooling) — but bounded (additive, macOS unaffected). No Apple account/entitlements; CloudKit + device (BAK-46) remain Leon-gated.
