# ADR-0004 — Ship as a Swift Package now; Xcode project when CloudKit/iOS land

**Status:** Accepted (2026-06-12)

## Context
A CloudKit-synced, iOS+macOS app ultimately needs an Xcode project with the iCloud
entitlement, an app group, and a signing team — things that can't be created from
the command line. But the foundation and most features (SwiftData, logic, the
agent loop, all the macOS surfaces) need none of that, and a Swift Package can be
created and driven entirely by an agent with `swift build`/`swift test`.

## Decision
Build as a **Swift Package** (`MustardKit` library + `Mustard` executable +
`MustardTests`) until CloudKit sync or the iOS target is needed. `build-app.sh`
assembles a signed `Mustard.app` from the SPM binary. Migrate to an `.xcodeproj`
(or add capabilities) only at the CloudKit/iOS step — and that step is **Leon-led**
(Apple Developer account, entitlements).

## Consequences
- The whole foundation + macOS feature set was built autonomously, no GUI step.
- `swift test`/`swift build` replace `xcodebuild` in all instructions.
- Design tokens namespaced `Theme` (not the module name `Mustard`) to avoid clashes.
- One future migration cost (SPM → Xcode) at the CloudKit boundary, accepted.

## Update — 2026-07-01 (BAK-108): iOS target via XcodeGen, additive

The iOS boundary arrived. Rather than convert the whole repo to an `.xcodeproj` (which
would move `swift build`/`swift test` to `xcodebuild` everywhere and churn CI), the iOS
app is **additive**: a committed `project.yml` (XcodeGen) defines an iOS app target
(`MustardMobile`) that compiles the platform-agnostic core (Models + Logic + Agent +
MustardContainer) directly, **excluding `Views/`** (AppKit). `ClaudeRunner`'s `Process`
path is `#if os(macOS)`-guarded with an iOS stub (the agent runs on the Mac only —
ADR-0003). macOS stays entirely on SPM: `swift build`/`swift test`/`build-app.sh` are
unchanged. Build the simulator app with `./build-ios.sh`. The generated `.xcodeproj` is
git-ignored; `project.yml` is the source of truth. CloudKit + device/TestFlight (BAK-46)
still need the Apple Developer account/entitlements — Leon-led, unchanged.
