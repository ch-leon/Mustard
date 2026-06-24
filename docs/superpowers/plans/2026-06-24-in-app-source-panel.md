# In-app Source Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open an agent item's source link (Jira / Shortcut / any URL) inside Mustard, in an embedded web view docked as a native trailing inspector.

**Architecture:** A pure, unit-tested `SourceLink` resolves an item (`Recommendation` / `MustardTask` / `OutputCard`) to a validated `http(s)` URL + display metadata. A `WKWebView` wrapped in `NSViewRepresentable` renders it inside a `.inspector` panel attached to `RootView`. An `@Observable SourcePanelController` (owned by `RootView`, injected into its subtree) holds which link is shown and whether the panel is open. A small `SourceLinkButton` affordance dispatches to the controller and is dropped into the recommendation, output-card, and task-detail surfaces.

**Tech Stack:** SwiftUI, SwiftData, WebKit (`WKWebView`), XCTest. Target macOS 14 (`.inspector` is 14+). The app is not sandboxed, so `WKWebView` networking needs no entitlement.

**Spec:** `docs/specs/2026-06-24-in-app-source-panel-design.md`

**Branch:** `feat/in-app-source-panel` (already created off `main`, with the spec committed).

---

## File structure

| File | Responsibility | New/Modify |
|------|----------------|------------|
| `Sources/MustardKit/Logic/SourceLink.swift` | Pure resolver: validate `sourceURL` (http/https allow-list), derive symbol/label, resolve from the three models | Create |
| `Tests/MustardTests/SourceLinkTests.swift` | Unit tests for `SourceLink` | Create |
| `Sources/MustardKit/Views/SourcePanelController.swift` | `@Observable` app-level panel state (`current`, `isPresented`, `open`) | Create |
| `Tests/MustardTests/SourcePanelControllerTests.swift` | Unit test for `open()` contract | Create |
| `Sources/MustardKit/Views/WebView.swift` | `NSViewRepresentable` over `WKWebView` + `WebViewModel` (loading/error/nav state) | Create |
| `Sources/MustardKit/Views/SourcePanelView.swift` | Inspector content: chrome, web view, empty/loading/error states | Create |
| `Sources/MustardKit/Views/SourceLinkButton.swift` | Shared affordance; renders nothing when there is no link | Create |
| `Sources/MustardKit/Views/RootView.swift` | Own controller, attach `.inspector`, ⌘⇧S toggle, inject environment | Modify |
| `Sources/MustardKit/Views/AgentConsoleView.swift` | Drop affordance into `RecommendationRow` + `OutputCardRow` | Modify |
| `Sources/MustardKit/Views/TaskDetailSheet.swift` | Drop affordance into the sheet header | Modify |

**Deliberate scope note (deviation from spec, flagged):** the spec lists "task rows" too. Today no `MustardTask` carries an `http(s)` `sourceURL` — meeting tasks store a vault note *path* (correctly rejected by the allow-list) and rec-derived tasks (`Schedule` / `I'll do it`) don't copy `rec.sourceURL`. So a task-row affordance would be permanently dormant *and* add noise to dense rows. This plan wires `TaskDetailSheet` (the natural task-inspection point) and defers list-row affordances. Follow-up (out of scope here): copy `rec.sourceURL` → `task.sourceURL` in the `Schedule` / `I'll do it` buttons so task sources become real, then add the row affordance.

---

## Task 1: `SourceLink` (pure resolver) + tests

**Files:**
- Create: `Sources/MustardKit/Logic/SourceLink.swift`
- Test: `Tests/MustardTests/SourceLinkTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MustardTests/SourceLinkTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class SourceLinkTests: XCTestCase {
    // MARK: scheme allow-list
    func test_https_resolves() {
        let link = SourceLink(sourceURL: "https://app.shortcut.com/story/3920", source: "shortcut", title: "Cadence")
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.url.absoluteString, "https://app.shortcut.com/story/3920")
        XCTAssertEqual(link?.label, "Cadence")
        XCTAssertEqual(link?.sourceKind, "shortcut")
    }

    func test_http_resolves() {
        XCTAssertNotNil(SourceLink(sourceURL: "http://example.com/x", source: "jira", title: "T"))
    }

    func test_fileScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "file:///etc/passwd", source: "vault", title: "T"))
    }

    func test_javascriptScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "javascript:alert(1)", source: "vault", title: "T"))
    }

    func test_obsidianScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "obsidian://open?vault=x", source: "vault", title: "T"))
    }

    func test_emptyAndNil_rejected() {
        XCTAssertNil(SourceLink(sourceURL: nil, source: "shortcut", title: "T"))
        XCTAssertNil(SourceLink(sourceURL: "", source: "shortcut", title: "T"))
        XCTAssertNil(SourceLink(sourceURL: "   ", source: "shortcut", title: "T"))
    }

    func test_vaultNotePath_rejected() {
        // Meeting tasks store a vault-relative note path here, not a web URL.
        XCTAssertNil(SourceLink(sourceURL: "Codeheroes work/Meetings/2026-06-01.md", source: "meeting", title: "T"))
    }

    // MARK: symbol / name mapping
    func test_symbol_perKind() {
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "shortcut", title: "T")?.symbol, "checklist")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "jira", title: "T")?.symbol, "ticket")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "gmail", title: "T")?.symbol, "envelope.fill")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "vault", title: "T")?.symbol, "books.vertical")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "carrier-pigeon", title: "T")?.symbol, "link")
    }

    func test_sourceName_perKind() {
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "shortcut", title: "T")?.sourceName, "Shortcut")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "jira", title: "T")?.sourceName, "Jira")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "carrier-pigeon", title: "T")?.sourceName, "Source")
    }

    // MARK: model resolvers
    func test_fromRecommendation() {
        let r = Recommendation(title: "Rec", source: "shortcut", sourceURL: "https://app.shortcut.com/s/1")
        XCTAssertEqual(SourceLink(from: r)?.label, "Rec")
        XCTAssertEqual(SourceLink(from: r)?.sourceKind, "shortcut")
    }

    func test_fromRecommendation_noURL_nil() {
        XCTAssertNil(SourceLink(from: Recommendation(title: "Vault note", source: "vault")))
    }

    func test_fromMustardTask() {
        let t = MustardTask(title: "Task")
        t.source = "jira"
        t.sourceURL = "https://jira.example.com/BROWSE-1"
        XCTAssertEqual(SourceLink(from: t)?.url.absoluteString, "https://jira.example.com/BROWSE-1")
    }

    func test_fromOutputCard_viaParent() {
        let r = Recommendation(title: "Parent", source: "gmail", sourceURL: "https://mail.example.com/t/1")
        let card = OutputCard(content: "done", kind: "summary", recommendation: r)
        XCTAssertEqual(SourceLink(from: card)?.url.absoluteString, "https://mail.example.com/t/1")
        XCTAssertEqual(SourceLink(from: card)?.label, "Parent")
    }

    func test_fromOutputCard_noParent_nil() {
        XCTAssertNil(SourceLink(from: OutputCard(content: "x", kind: "summary")))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SourceLinkTests`
Expected: FAIL — compile error "cannot find 'SourceLink' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/MustardKit/Logic/SourceLink.swift`:

```swift
import Foundation

/// Pure resolver: turns an item's stored `sourceURL` (+ source string) into an
/// openable web link, or `nil`. The scheme allow-list (`http`/`https`) is a
/// security boundary — a `sourceURL` can come from the agent or an external
/// source, so we never let a `file:`/`javascript:`/other-scheme string drive a
/// load. Vault note paths (meeting tasks) have no scheme and are rejected.
public struct SourceLink: Equatable {
    public let url: URL
    /// The item's title — shown as the panel header text.
    public let label: String
    /// Lowercased raw source string (e.g. "shortcut", "jira", "gmail", "vault").
    public let sourceKind: String

    public init?(sourceURL: String?, source: String, title: String) {
        guard
            let raw = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        self.url = url
        self.label = title
        self.sourceKind = source.lowercased()
    }

    /// SF Symbol for the source glyph. Mirrors `SourceBadge` for gmail/vault and
    /// adds ticket-ish symbols for jira/shortcut (which `SourceBadge` can't map yet).
    public var symbol: String {
        switch sourceKind {
        case "shortcut": "checklist"
        case "jira": "ticket"
        case "gmail": "envelope.fill"
        case "vault": "books.vertical"
        default: "link"
        }
    }

    /// Friendly source name (header tooltip / accessibility).
    public var sourceName: String {
        switch sourceKind {
        case "shortcut": "Shortcut"
        case "jira": "Jira"
        case "gmail": "Gmail"
        case "vault": "Vault"
        default: "Source"
        }
    }
}

public extension SourceLink {
    init?(from rec: Recommendation) {
        self.init(sourceURL: rec.sourceURL, source: rec.source, title: rec.title)
    }

    init?(from task: MustardTask) {
        self.init(sourceURL: task.sourceURL, source: task.source, title: task.title)
    }

    /// Output cards have no URL of their own — resolve via the parent recommendation.
    init?(from card: OutputCard) {
        guard let rec = card.recommendation else { return nil }
        self.init(from: rec)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SourceLinkTests`
Expected: PASS (all 13 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/SourceLink.swift Tests/MustardTests/SourceLinkTests.swift
git commit -m "feat(source-panel): pure SourceLink resolver with http/https allow-list" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `SourcePanelController` (@Observable) + test

**Files:**
- Create: `Sources/MustardKit/Views/SourcePanelController.swift`
- Test: `Tests/MustardTests/SourcePanelControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/SourcePanelControllerTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class SourcePanelControllerTests: XCTestCase {
    func test_open_setsCurrentAndPresents() {
        let controller = SourcePanelController()
        XCTAssertNil(controller.current)
        XCTAssertFalse(controller.isPresented)

        let link = SourceLink(sourceURL: "https://app.shortcut.com/s/1", source: "shortcut", title: "T")!
        controller.open(link)

        XCTAssertEqual(controller.current, link)
        XCTAssertTrue(controller.isPresented)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SourcePanelControllerTests`
Expected: FAIL — "cannot find 'SourcePanelController' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/MustardKit/Views/SourcePanelController.swift`:

```swift
import SwiftUI

/// App-level state for the source inspector: which link is shown and whether the
/// panel is open. Owned by `RootView` and injected into its subtree via the
/// environment, mirroring how `AgentService` is provided. A single reused web
/// view re-points each time `open` is called (no tabs).
@Observable
public final class SourcePanelController {
    public var current: SourceLink?
    public var isPresented: Bool = false

    public init() {}

    public func open(_ link: SourceLink) {
        current = link
        isPresented = true
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SourcePanelControllerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Views/SourcePanelController.swift Tests/MustardTests/SourcePanelControllerTests.swift
git commit -m "feat(source-panel): SourcePanelController for inspector state" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `WebView` + `WebViewModel`

Views are verified by build + eye (project rule), so no unit test here.

**Files:**
- Create: `Sources/MustardKit/Views/WebView.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/MustardKit/Views/WebView.swift`:

```swift
import SwiftUI
import WebKit

/// Loading / navigation state for the embedded web view, observed by the panel.
@Observable
final class WebViewModel {
    var isLoading = false
    var loadFailed = false
    var canGoBack = false
    var canGoForward = false
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

/// `WKWebView` wrapped for SwiftUI. Uses the shared persistent website data store
/// so a sign-in (e.g. Jira/Shortcut SSO) survives across launches.
struct WebView: NSViewRepresentable {
    let url: URL
    let model: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        model.webView = view
        context.coordinator.lastRequested = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastRequested != url else { return }
        context.coordinator.lastRequested = url
        view.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: WebViewModel
        var lastRequested: URL?
        init(_ model: WebViewModel) { self.model = model }

        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
            model.isLoading = true
            model.loadFailed = false
        }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            model.isLoading = false
            model.canGoBack = w.canGoBack
            model.canGoForward = w.canGoForward
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
            failed(w)
        }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
            failed(w)
        }
        private func failed(_ w: WKWebView) {
            model.isLoading = false
            model.loadFailed = true
            model.canGoBack = w.canGoBack
            model.canGoForward = w.canGoForward
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/WebView.swift
git commit -m "feat(source-panel): WKWebView wrapper with persistent login + nav state" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `SourcePanelView` (inspector content)

**Files:**
- Create: `Sources/MustardKit/Views/SourcePanelView.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/MustardKit/Views/SourcePanelView.swift`:

```swift
import SwiftUI

/// The trailing-inspector content: calm chrome over an embedded web view, with
/// empty / loading / error states. Reads the current link from the controller.
struct SourcePanelView: View {
    @Environment(SourcePanelController.self) private var panel
    @Environment(\.openURL) private var openURL
    @State private var web = WebViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let link = panel.current {
                chrome(link)
                Divider().overlay(Theme.Palette.hairline)
                ZStack {
                    WebView(url: link.url, model: web)
                    if web.loadFailed { errorState(link) }
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Palette.bg)
        .onChange(of: panel.current?.url) { _, _ in
            web.loadFailed = false
            web.isLoading = true
        }
    }

    private func chrome(_ link: SourceLink) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: link.symbol)
                    .font(.system(size: 13)).foregroundStyle(Theme.Palette.agent)
                Text(link.label)
                    .font(Theme.Fonts.title).foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Button { openURL(link.url) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                    .help("Open in your browser")
                Button { panel.isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                    .help("Close panel")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            HStack(spacing: 10) {
                Button { web.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(!web.canGoBack)
                Button { web.goForward() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(!web.canGoForward)
                Button { web.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                Text(link.url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if web.isLoading { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(Theme.Palette.textTertiary)
            Text("Select an item with a source to preview it here.")
                .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private func errorState(_ link: SourceLink) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26))
                .foregroundStyle(Theme.Palette.warning)
            Text("This page needs sign-in or is offline.")
                .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button { openURL(link.url) } label: {
                Label("Open in browser", systemImage: "arrow.up.right")
            }
            .controlSize(.small).tint(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24).background(Theme.Palette.bg)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/SourcePanelView.swift
git commit -m "feat(source-panel): inspector content with chrome + empty/loading/error states" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `SourceLinkButton` (shared affordance)

The `@Environment(SourcePanelController.self)` lives on an **inner** view that is only instantiated when a link exists — so a link-less item never requires the controller (keeps previews / non-injected contexts safe).

**Files:**
- Create: `Sources/MustardKit/Views/SourceLinkButton.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/MustardKit/Views/SourceLinkButton.swift`:

```swift
import SwiftUI
import AppKit

/// A compact source-glyph button that opens the item's source in the inspector.
/// Renders nothing when the item has no openable (http/https) source.
struct SourceLinkButton: View {
    let link: SourceLink?

    init(rec: Recommendation) { link = SourceLink(from: rec) }
    init(task: MustardTask) { link = SourceLink(from: task) }
    init(card: OutputCard) { link = SourceLink(from: card) }

    var body: some View {
        if let link { SourceLinkButtonInner(link: link) }
    }
}

private struct SourceLinkButtonInner: View {
    @Environment(SourcePanelController.self) private var panel
    @Environment(\.openURL) private var openURL
    let link: SourceLink

    var body: some View {
        Button { panel.open(link) } label: {
            Image(systemName: link.symbol).font(.system(size: 12))
                .foregroundStyle(Theme.Palette.agent)
        }
        .buttonStyle(.plain)
        .help("Open source in panel — \(link.sourceName)")
        .contextMenu {
            Button("Open in panel") { panel.open(link) }
            Button("Open in browser") { openURL(link.url) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/SourceLinkButton.swift
git commit -m "feat(source-panel): SourceLinkButton affordance (hidden when no link)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Wire the inspector into `RootView`

**Files:**
- Modify: `Sources/MustardKit/Views/RootView.swift`

- [ ] **Step 1: Add the controller state**

In `RootView` (after `@State private var showCommandBar = false`, around line 48), add:

```swift
    @State private var sourcePanel = SourcePanelController()
```

- [ ] **Step 2: Attach the inspector + inject the controller**

In `body`, the root is the `HStack { sidebar; Divider…; Group { … } }` chain that currently ends with `.background(Theme.Palette.bg)`, `.overlay { … }`, `.background { … }`, `.preferredColorScheme(.light)`. Insert the inspector and environment **after** the hidden-shortcut `.background { … }` block and **before** `.preferredColorScheme(.light)`, so the environment wraps both the screens and the inspector content:

```swift
        // (existing) .background { hidden ⌘K trigger button … }
        .inspector(isPresented: $sourcePanel.isPresented) {
            SourcePanelView()
                .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
        }
        .environment(sourcePanel)
        .preferredColorScheme(.light)
```

- [ ] **Step 3: Add the ⌘⇧S toggle**

In the existing hidden-trigger `.background { … }` block (currently just the ⌘K button), add a second hidden button alongside it so the closure returns both (wrap in a `Group`):

```swift
        .background {
            Group {
                // Hidden trigger: ⌘K opens the command bar while the window is key.
                Button("") { showCommandBar.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                // Hidden trigger: ⌘⇧S toggles the source inspector.
                Button("") { sourcePanel.isPresented.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            .opacity(0)
        }
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Views/RootView.swift
git commit -m "feat(source-panel): attach trailing inspector + ⌘⇧S toggle in RootView" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Affordance in `RecommendationRow` + `OutputCardRow`

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift`

- [ ] **Step 1: Add to `RecommendationRow`**

In `RecommendationRow.body`, the title `HStack` currently is (around lines 221-235):

```swift
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.Palette.agent)
                Text(rec.title).font(Theme.Fonts.title).foregroundStyle(Theme.Palette.textPrimary)
                if rec.action.isGated {
                    Label("Always needs you", systemImage: "lock")
                        .labelStyle(.titleAndIcon).font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .help("Email, Slack, and ticket actions are always gated regardless of trust.")
                }
                Spacer()
                Button(expanded ? "Hide" : "Review") {
                    withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.plain).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.accent)
            }
```

Insert `SourceLinkButton(rec: rec)` immediately **before** the `Button(expanded ? "Hide" : "Review")` (so it sits just left of the Review button, after the `Spacer()`):

```swift
                Spacer()
                SourceLinkButton(rec: rec)
                Button(expanded ? "Hide" : "Review") {
                    withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.plain).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.accent)
```

- [ ] **Step 2: Add to `OutputCardRow`**

In `OutputCardRow.body`, the title `HStack` ends (around lines 512-517) with:

```swift
                Spacer()
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.accent)
```

Insert `SourceLinkButton(card: card)` immediately **before** the `Button(expanded ? "Less" : "More")`:

```swift
                Spacer()
                SourceLinkButton(card: card)
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.accent)
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 4: Commit**

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(source-panel): open-source affordance on recommendation + output rows" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Affordance in `TaskDetailSheet`

**Files:**
- Modify: `Sources/MustardKit/Views/TaskDetailSheet.swift`

- [ ] **Step 1: Add to the sheet header**

The `header` computed property (around lines 155-162) is:

```swift
    private var header: some View {
        HStack {
            Text("Task").font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button("Done") { dismiss() }.controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
```

Insert `SourceLinkButton(task: task)` between `Spacer()` and the `Done` button:

```swift
    private var header: some View {
        HStack {
            Text("Task").font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            SourceLinkButton(task: task)
            Button("Done") { dismiss() }.controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/TaskDetailSheet.swift
git commit -m "feat(source-panel): open-source affordance in task detail header" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Full verification

- [ ] **Step 1: Run the whole test suite**

Run: `swift test`
Expected: PASS — the prior 73 cases plus the new `SourceLinkTests` (13) and `SourcePanelControllerTests` (1). No failures.

- [ ] **Step 2: Build the app**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Manual confirmation (Leon)**

The in-session shell cannot screenshot the native app, so Leon confirms the live look:

```bash
./build-app.sh && open build/Mustard.app
```

Check:
- A recommendation with a real `sourceURL` (e.g. a Gmail-sourced rec) shows the source glyph; clicking it opens the inspector on the right with the page loading.
- ⌘⇧S toggles the inspector; the `xmark` closes it.
- Back / forward / reload and the `↗` "open in browser" work; the error state appears for a page that fails to load, with a working "Open in browser" fallback.
- The empty state shows when the panel is opened (⌘⇧S) with nothing selected.
- Login persistence: sign in to a source once, quit, relaunch — the session is still there.

- [ ] **Step 4: (No commit)** — verification only.

---

## Self-review

**Spec coverage:**
- Decision 1 (embedded web view, generic) → Task 3 (`WebView`), opens any `http(s)` URL.
- Decision 2 (trailing `.inspector`) → Task 6.
- Decision 3 (recs / tasks / output cards) → `SourceLink` resolvers (Task 1) + Tasks 7-8. Task-list rows deliberately deferred (flagged in File structure — dormant today).
- Decision 4 (persistent login) → `WKWebsiteDataStore.default()` in Task 3.
- `SourceLink` pure + http/https allow-list + label/icon + card-via-parent → Task 1 (all covered by tests).
- Chrome (icon, title, back/fwd/reload, open-in-browser, close) + empty/loading/error states → Task 4.
- `SourceLinkButton` hidden when nil → Task 5.
- No schema change → confirmed; no model/container edits in any task.
- Security (scheme allow-list) → Task 1 tests `file:`, `javascript:`, `obsidian:`, vault path all rejected.
- Testing plan (`SourceLinkTests` cases; views build+eye) → Tasks 1, 9.

**Placeholder scan:** none — every code step shows complete code; every run step has an exact command + expected result.

**Type consistency:** `SourceLink(sourceURL:source:title:)` and `SourceLink(from:)` used identically across Tasks 1, 5. `SourcePanelController.open(_:)` / `.isPresented` / `.current` consistent across Tasks 2, 4, 5, 6. `WebViewModel` methods (`goBack`/`goForward`/`reload`) and flags (`isLoading`/`loadFailed`/`canGoBack`/`canGoForward`) consistent across Tasks 3, 4. `SourceLinkButton` initializers (`rec:`/`task:`/`card:`) match their call sites in Tasks 7-8.
