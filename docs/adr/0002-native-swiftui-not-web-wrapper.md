# ADR-0002 — Native SwiftUI, not an Electron/Tauri web wrapper

**Status:** Accepted (2026-06-12)

## Context
The predecessor was a React/Vite web app. Options for the desktop app: reuse the
web UI in a wrapper (Electron, or Tauri which also targets iOS), or rewrite native
in SwiftUI. Two signature features — an **always-on-top floating HUD** (Blitz-style)
and especially a **notch surface** (boring-notch/NotchNook-style) — are deeply
native: every notch app is AppKit/SwiftUI, and there is no good web-wrapper story
for hovering and expanding a panel positioned around the physical notch. Leon also
wanted true native feel and was willing to rewrite, and wants iOS later.

## Decision
Build **native SwiftUI** (shared macOS + iOS codebase later). Do not wrap the web
UI. The agent loop, which is TypeScript-native, is replaced by a Swift `Process`
shell-out to the `claude` CLI (ADR-0003) rather than a Node sidecar.

## Consequences
- Notch + hover panels are first-class and behave correctly (`NSPanel`,
  non-activating, status-bar level).
- The React UI and its components are not reused; the look is rebuilt (ADR-0005).
- One Swift codebase can serve macOS and iOS.
- Loses instant web-wrapper reuse; accepted given the native ambitions.
