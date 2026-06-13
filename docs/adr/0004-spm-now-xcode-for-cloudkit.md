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
