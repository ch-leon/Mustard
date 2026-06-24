# In-app source panel — design

- **Date:** 2026-06-24
- **Status:** Approved (design); ready for implementation plan
- **Scope:** A side panel that opens an agent item's source link (Jira, Shortcut, or any URL) inside Mustard, as an embedded web view.

## Problem & context

Every `Recommendation` already stores a `sourceURL`, and `MustardTask` stores one too — but **nothing in the app opens it today** (there is no `NSWorkspace.open`/`openURL` anywhere). When triaging an agent recommendation, you often need to see its source (the Jira issue, the Shortcut story) to decide approve / edit / reject, and today that means leaving the app.

This adds an in-app panel that shows the source without leaving Mustard.

Note: Jira and Shortcut are **not yet wired as ingest sources** — `SourceID` is currently `gmail` + `vault` only. This feature does **not** depend on that. `Recommendation.source` is a free-text string and `sourceURL` is plumbed end-to-end, so the panel works for any item that carries an `http(s)` `sourceURL` regardless of which source produced it.

## Decisions

| # | Decision | Rationale | Rejected alternatives |
|---|----------|-----------|-----------------------|
| 1 | **Embedded web view** (`WKWebView`), generic | Source-agnostic — one backend opens Jira, Shortcut, and any URL on day one. Full fidelity; can interact. | **Native API render** (fetch via REST/MCP, draw in house style): calmer and auth-free but per-source work and only covers sources with a client. **Open in real browser only**: leaves the app — fails the "in-app" goal. |
| 2 | **Native trailing `.inspector`** (macOS 14) | Toggles open/closed instead of permanently splitting the window; app-level so it serves the Agent console now and tasks later; resizable; no extra window to manage. | **Inline `HSplit` in the Agent console**: console-only, always consumes width. **Separate floating window** (Hover-panel sibling): another window to manage. |
| 3 | **Opens anywhere a `sourceURL` resolves** | Recommendations, tasks, and output cards — fully general. | Recommendations-only / recs+tasks: smaller, but the inspector is app-level so the marginal cost of full coverage is small. |
| 4 | **Persistent login** (shared `WKWebsiteDataStore.default()`) | Log in once per service; the session survives app launches. WebKit has its own cookie jar — there is no way to share Safari/Chrome cookies, so a one-time in-app sign-in for authed tools is unavoidable and accepted. | Non-persistent store (would force re-login constantly). |

## Architecture

Follows the project separation rule: the one **decision** (URL validation, label/icon) is pure and unit-tested in `Logic/`; everything else renders and dispatches in `Views/`.

### `Logic/SourceLink.swift` — pure, TDD'd

The single source of truth for "does this item have an openable source, and what is it." A value type plus factory:

```
struct SourceLink {
    let url: URL          // validated, http/https only
    let label: String     // display title for the panel header
    let sourceKind: String // drives icon/label, e.g. "shortcut", "jira", "gmail", "vault", ""
}
```

- `init?(sourceURL: String?, source: String, title: String)` — the core resolver. Returns `nil` unless `sourceURL` parses to a real `URL` whose scheme is **`http` or `https`** (allow-list). This is a real, if small, security boundary: a `sourceURL` can originate from the agent or an external source, so we never let a malformed/hostile string drive a `file:`/`javascript:`/other-scheme load.
- Convenience resolvers: `init?(from: Recommendation)`, `init?(from: MustardTask)`, `init?(from: OutputCard)`. `OutputCard` resolves via its parent `recommendation?.sourceURL`.
- `sourceKind` → SF Symbol + label via a small pure mapping (e.g. `shortcut`/`jira` → ticket-ish symbol; default → `link`).

Consequence worth noting: `MustardTask.sourceURL` for **meeting tasks** is a *vault-relative note path*, not a web URL — it correctly resolves to `nil` (it is not a web source). Opening vault notes is out of scope (see below).

### `Views/WebView.swift` — `NSViewRepresentable`

Thin wrapper over `WKWebView`, configured with the shared persistent `WKWebsiteDataStore.default()`. Binds to the controller's current URL and reports load state back (loading, finished, failed, title, canGoBack/Forward).

### `Views/SourcePanelController.swift` — `@Observable`

App-level panel state, injected via the environment like `AgentService`:

```
@Observable final class SourcePanelController {
    var current: SourceLink?
    var isPresented: Bool = false
    func open(_ link: SourceLink) { current = link; isPresented = true }
}
```

A single reused web view that re-points each time `open` is called (no tabs).

### `Views/SourcePanelView.swift` — the inspector content

Calm chrome + the web view + states:
- **Header:** source icon (agent-purple glyph), title (truncated), open-in-real-browser `↗` (`NSWorkspace.open`), close `✕`.
- **Nav line:** back / forward / reload + the current URL (monospace, muted).
- **Web area:** the `WebView`.
- **States:** empty ("Select an item with a source to preview it here."), loading (thin progress indicator), and error ("This page needs sign-in or is offline." + an **Open in browser ↗** fallback — also the escape hatch for SSO-heavy pages that misbehave in an embedded view).

### `Views/SourceLinkButton.swift` — the shared affordance

`SourceLinkButton(item:)` computes `SourceLink(from: item)`; renders **nothing** when it is `nil`, otherwise a small source-icon button. On tap → `sourcePanel.open(link)`. Context menu: open in panel / open in browser / copy link.

## Data model

**No schema change.** `Recommendation.sourceURL` and `MustardTask.sourceURL` already exist; `OutputCard` reaches a URL through its parent recommendation. CloudKit-shaped defaults are untouched (ADR-0001).

## Integration points (edits)

- **`Views/RootView.swift`** — owns `@State private var sourcePanel = SourcePanelController()`; injects it with `.environment(sourcePanel)`; attaches `.inspector(isPresented: $sourcePanel.isPresented) { SourcePanelView() }`; adds a hidden **⌘⇧S** toggle button mirroring the existing hidden **⌘K** command-bar button. No toolbar button — consistent with the deliberate "no toolbar chrome" of the calm sidebar; opening is via the row affordance or ⌘⇧S, closing via the panel `✕` or ⌘⇧S.
- **`Views/AgentConsoleView.swift`** — drop `SourceLinkButton` into `RecommendationRow` (near the title/provenance row) and `OutputCardRow`.
- **Task surfaces** — `SourceLinkButton` in the task rows and `TaskDetailSheet`.
- The executable (`Sources/Mustard/MustardApp.swift`) needs **no change** — the controller lives in `RootView`'s subtree, not in the separate Hover/Notch panel windows.

## Security

- **Scheme allow-list** (`http`/`https`) in `SourceLink`, enforced before any load (see above).
- **Persistent cookies** live in the app's WebKit data store — acceptable for a single-user, local-first app.
- `WKWebView` renders untrusted remote content inside WebKit's own sandbox; "open in browser" is always available as a fallback.

## Testing plan

- **`Tests/MustardTests/SourceLinkTests.swift`** (new, pure, TDD):
  - valid `https://…` and `http://…` → a link;
  - `file:…`, `javascript:…`, `obsidian://…`, empty string, `nil`, and non-URL garbage → `nil`;
  - vault-relative note path (meeting-task style) → `nil`;
  - label/icon (`sourceKind`) mapping for `shortcut`, `jira`, `gmail`, `vault`, unknown;
  - resolution from `Recommendation`, `MustardTask`, and `OutputCard` (including card-via-parent and the `nil` cases).
- **Views** (`WebView`, `SourcePanelView`, `SourceLinkButton`, the `.inspector` wiring): verified by `swift build` + eye — Leon confirms the live look (the in-session shell cannot screenshot the native app). Per the project testing rules, views are not unit-tested.
- Whole suite (`swift test`) and `swift build` must pass before the change is "done."

## Feasibility — verified 2026-06-24

- **Not sandboxed** (no `.entitlements`; `build-app.sh` ad-hoc signs only) → `WKWebView` networking needs no entitlement. If the app is ever sandboxed, add `com.apple.security.network.client`.
- **`Package.swift` is `.macOS(.v14)`** → `.inspector(isPresented:)` is available.
- **`⌘⇧S` is free** (taken: `⌘⇧H`, `⌘⇧N`, `⌘K`).

## Out of scope (YAGNI)

- Native API/MCP render of tickets (decision 1 chose web-view-only).
- Tabs / multi-page history beyond the web view's own back/forward.
- Per-source theming or auth token management.
- Opening vault notes / non-web sources (e.g. meeting-task note paths) — could later route to `obsidian://`, not now.
- Acting on the source beyond what the live web UI already provides; structured actions remain in Mustard's gated recommendation → OutputCard loop.
