## BAK-110 — iOS app shell

The bottom-tab skeleton every mobile screen plugs into (BAK-108 unblocked this).

- `MustardMobileApp` wires the shared `MustardContainer` + `AgentService` (agent execution is a Mac-only no-op on iOS, ADR-0003).
- `MobileRootView`: `TabView` in mobile order **Today · Week · Board · Agent**; Agent accent purple; **Agent tab badge** = pending triage count.
- **FAB** on Today + Board → "New task — coming soon" (create form is desktop-only).
- **Shared `MobileFilters`** (owner + area) across Board + Week — real screens (BAK-114/116) consume it.
- Tab content is placeholder until BAK-113/114/116/119.

### Checks
iOS `build-ios.sh` → BUILD SUCCEEDED · macOS swift build clean · swift test 419 pass/1 skip (SPM untouched).

### Risk
Medium — iOS-only UI; macOS unaffected.
