# BAK-110 — iOS app shell (bottom-tab nav, badge, FAB, shared filters)

**Run:** 20260701-104519 · **Milestone:** Redesign · iOS companion · **Risk:** medium (new iOS UI; macOS untouched)
**Blocked-by:** BAK-108 (done).

- MustardMobileApp wires the shared `MustardContainer` + `AgentService` (agent exec is a Mac-only no-op on iOS).
- `MobileRootView`: bottom `TabView` in mobile order **Today · Week · Board · Agent**; accent purple on Agent, blue elsewhere; **Agent tab badge** = pending triage count (`AgentInbox.pendingRecCount`).
- **FAB** (dark "+") on Today + Board → "✦ New task — coming soon" toast (create form is desktop-only).
- **Shared `MobileFilters`** (owner + area) passed to Board + Week stubs — one instance, changes propagate (real screens BAK-114/116 consume it).
- Placeholder tab content until BAK-113/114/116/119.
