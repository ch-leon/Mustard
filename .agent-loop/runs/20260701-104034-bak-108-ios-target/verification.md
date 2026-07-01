# BAK-108 — iOS app target + Xcode(Gen) migration (ADR-0004)

**Run:** 20260701-104034-bak-108-ios-target · **Milestone:** Redesign · iOS foundation · **Risk:** HIGH (structural + new build tooling)

**Approach (Leon-approved: XcodeGen, simulator-first):** additive. `project.yml` (XcodeGen)
defines an iOS app `MustardMobile` compiling the platform-agnostic core (Models + Logic +
Agent + MustardContainer), excluding `Views/` (AppKit). `ClaudeRunner` Process path is
`#if os(macOS)`-guarded with an iOS stub. macOS stays 100% on SPM — swift build/test/
build-app.sh unchanged. `build-ios.sh` = xcodegen generate + xcodebuild simulator.
The generated .xcodeproj is git-ignored (project.yml is source of truth).

## Verified
- iOS: `xcodebuild ... -destination 'iOS Simulator'` → **BUILD SUCCEEDED** (core links for iOS).
- macOS: `swift build` clean, `swift test` 419 pass/1 skip (untouched).

## Scope
Foundation only — a stub `MobileRootView` proving the core links. Bottom-tab shell + screens
are BAK-110+. No Apple account needed (simulator, CODE_SIGNING_ALLOWED=NO). CloudKit/device
(BAK-46) still Leon-gated.
