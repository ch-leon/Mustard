# Agent Recommendations Master-Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Agent console's click-`Review`-to-expand-inline recommendations with a master-detail layout — selecting a recommendation opens its detail on the right — and add a default-on setting that controls whether the source panel auto-opens on selection.

**Architecture:** Extract the inline triage drawer + actions into a standalone `RecommendationDetailView`. Slim `RecommendationRow` to a compact, selectable summary. `AgentConsoleView` becomes an `HSplitView` (master list │ detail), holds the selection, and — on explicit selection — auto-opens the source inspector (the trailing `.inspector` from the merged source-panel feature) when the setting is on and the rec has a web source. A small pure `RecommendationSelection` enum holds the testable decisions.

**Tech Stack:** SwiftUI, SwiftData, XCTest. macOS 14. Reuses `SourcePanelController` / `SourceLink` / `SourceLinkButton` (already on `main`).

**Spec:** `docs/specs/2026-06-24-agent-recs-master-detail-design.md`

**Branch:** `feat/agent-recs-master-detail` (off `main`, which already has the source panel + ownership-badge merged). Spec already committed.

---

## File structure

| File | Responsibility | New/Modify |
|------|----------------|------------|
| `Sources/MustardKit/Logic/RecommendationSelection.swift` | Pure: `nextSelection(current:pending:)` + `shouldAutoOpenSource(settingOn:rec:)` | Create |
| `Tests/MustardTests/RecommendationSelectionTests.swift` | Unit tests for the above | Create |
| `Sources/MustardKit/Views/RecommendationDetailView.swift` | The triage workspace for one rec (always-expanded drawer + actions), shown in the detail pane | Create |
| `Sources/MustardKit/Views/AgentConsoleView.swift` | Slim `RecommendationRow` to a selectable summary; restructure `AgentConsoleView` into master-detail; selection + auto-open + header toggle | Modify |

Note: `RecommendationRow`, `ProvenancePill`, `SourceGroupHeader`, `FlowChips`, `OutputCardRow` all currently live inside `AgentConsoleView.swift`. This plan keeps them there. `ProvenancePill`, `FlowChips`, `SourceBadge`, `SourceLinkButton` are reused as-is.

---

## Task 1: `RecommendationSelection` (pure) + tests

**Files:**
- Create: `Sources/MustardKit/Logic/RecommendationSelection.swift`
- Test: `Tests/MustardTests/RecommendationSelectionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MustardTests/RecommendationSelectionTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class RecommendationSelectionTests: XCTestCase {
    // nextSelection
    func test_nextSelection_keepsCurrentWhenStillPending() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: a, pending: [a, b]) === a)
    }
    func test_nextSelection_fallsBackToFirstWhenCurrentGone() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: a, pending: [b]) === b)
    }
    func test_nextSelection_firstOnArrival() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: nil, pending: [a, b]) === a)
    }
    func test_nextSelection_nilWhenEmpty() {
        XCTAssertNil(RecommendationSelection.nextSelection(current: nil, pending: []))
    }
    // shouldAutoOpenSource
    func test_shouldAutoOpenSource_onWithSource() {
        let r = Recommendation(title: "T", source: "shortcut", sourceURL: "https://app.shortcut.com/s/1")
        XCTAssertTrue(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: r))
    }
    func test_shouldAutoOpenSource_onWithoutSource() {
        let r = Recommendation(title: "Vault note", source: "vault")
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: r))
    }
    func test_shouldAutoOpenSource_offWithSource() {
        let r = Recommendation(title: "T", source: "jira", sourceURL: "https://jira.example.com/1")
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: false, rec: r))
    }
    func test_shouldAutoOpenSource_nilRec() {
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: nil))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RecommendationSelectionTests`
Expected: FAIL — "cannot find 'RecommendationSelection' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/MustardKit/Logic/RecommendationSelection.swift`:

```swift
import Foundation

/// Pure selection helpers for the Agent recommendations master-detail list.
public enum RecommendationSelection {
    /// Which recommendation should be selected, given the current selection and the
    /// live pending queue: keep the current one if it's still pending, otherwise fall
    /// back to the top of the queue (or nil when empty). Identity-based (`===`) so it
    /// never dereferences a recommendation that has left the queue.
    public static func nextSelection(current: Recommendation?, pending: [Recommendation]) -> Recommendation? {
        if let current, pending.contains(where: { $0 === current }) { return current }
        return pending.first
    }

    /// Whether selecting `rec` should also auto-open the source panel: only when the
    /// setting is on AND the rec resolves to an http(s) source link.
    public static func shouldAutoOpenSource(settingOn: Bool, rec: Recommendation?) -> Bool {
        guard settingOn, let rec else { return false }
        return SourceLink(from: rec) != nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RecommendationSelectionTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/RecommendationSelection.swift Tests/MustardTests/RecommendationSelectionTests.swift
git commit -m "feat(agent-recs): pure RecommendationSelection (next-selection + auto-open decision)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `RecommendationDetailView`

The triage workspace for one rec — the old inline drawer + actions, always-expanded and standalone. No unit test (view → build + eye). It's unused until Task 3 wires it in; that's fine (it compiles standalone).

**Files:**
- Create: `Sources/MustardKit/Views/RecommendationDetailView.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/MustardKit/Views/RecommendationDetailView.swift`:

```swift
import SwiftUI
import SwiftData

/// The triage workspace for one recommendation — shown in the Agent console's
/// master-detail right pane. Provenance, action + confidence, reasoning, re-bucket
/// chips, original source, the editable draft, comment, and the outcome actions.
/// Lifted from the old inline `RecommendationRow` drawer (always expanded, standalone).
struct RecommendationDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    let rec: Recommendation
    @State private var commenting = false
    @State private var commentText = ""

    private var confidenceSegments: Int { Int((rec.confidence * 5).rounded(.down)) }
    private var confidenceColor: Color {
        rec.confidence >= 0.7 ? Theme.Palette.done
            : rec.confidence >= 0.4 ? Color(hex: "#BA7517") : Color(hex: "#D85A30")
    }
    private var draftOrBody: String { rec.draft.isEmpty ? rec.body : rec.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProvenancePill(rec: rec)
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(Theme.Palette.agent)
                Text(rec.title).font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
                if rec.action.isGated {
                    Label("Always needs you", systemImage: "lock")
                        .labelStyle(.titleAndIcon).font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .help("Email, Slack, and ticket actions are always gated regardless of trust.")
                }
                Spacer()
            }
            actionAndConfidence
            if !rec.reasoning.isEmpty {
                (Text("Why · ").foregroundStyle(Theme.Palette.textTertiary)
                    + Text(rec.reasoning).foregroundStyle(Theme.Palette.textSecondary))
                    .font(Theme.Fonts.meta)
            }
            drawer
            outcomes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionAndConfidence: some View {
        HStack(spacing: 8) {
            Text(rec.action.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#534AB7"))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.Palette.agent.opacity(0.14), in: Capsule())
            Spacer()
            Text("confidence").font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary)
            Text(String(format: "%.2f", rec.confidence))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(confidenceColor)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < confidenceSegments ? confidenceColor : Theme.Palette.surface)
                        .frame(width: 16, height: 5)
                }
            }
        }
    }

    @ViewBuilder private var drawer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RE-BUCKET").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            FlowChips(selected: rec.action) { rec.action = $0 }
        }

        if let original = rec.originalSource, !original.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ORIGINAL EMAIL").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(original).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                    .textSelection(.enabled)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("PROPOSED DRAFT").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            TextEditor(text: Binding(get: { rec.draft }, set: { rec.draft = $0 }))
                .font(Theme.Fonts.meta)
                .frame(minHeight: 80, maxHeight: 220)
                .padding(6)
                .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
        }

        if commenting {
            TextField("Feedback to the agent…", text: $commentText)
                .textFieldStyle(.roundedBorder).font(Theme.Fonts.meta)
                .onSubmit { agent.comment(rec, commentText); commenting = false }
        } else if !rec.comment.isEmpty {
            (Text("Comment · ").foregroundStyle(Theme.Palette.textTertiary)
                + Text(rec.comment).foregroundStyle(Theme.Palette.textSecondary))
                .font(Theme.Fonts.meta)
        }
    }

    private var outcomes: some View {
        HStack(spacing: 8) {
            if rec.action == .fyi {
                Button("Keep") { agent.keep(rec) }
                    .buttonStyle(.borderedProminent).tint(Theme.Palette.accent)
                    .controlSize(.small)
                    .help("File this to your knowledge base log, then clear it.")
                Spacer()
                Button("Dismiss", role: .destructive) { rec.decision = .denied }
                    .controlSize(.small)
                    .help("You've seen it — remove it. Nothing is stored.")
            } else {
                Button("Approve") { Task { await agent.decide(rec, .approved) } }
                    .buttonStyle(.borderedProminent).tint(Theme.Palette.accent)
                    .controlSize(.small).disabled(agent.isExecuting)
                Button("Comment") { commenting.toggle(); commentText = rec.comment }
                    .controlSize(.small)
                Menu("Snooze") {
                    Button("1 hour") { agent.snooze(rec, until: .now.addingTimeInterval(3600)) }
                    Button("This evening") { agent.snooze(rec, until: eveningOrSoon()) }
                    Button("Tomorrow") { agent.snooze(rec, until: tomorrow9()) }
                }
                .controlSize(.small).fixedSize()
                Button("Schedule") {
                    rec.decision = .scheduled
                    let task = MustardTask(title: rec.title); task.notes = draftOrBody
                    let cal = Calendar.current
                    if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) {
                        task.scheduledAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                        task.status = .planned
                    }
                    context.insert(task)
                }
                .controlSize(.small)
                Button("I'll do it") {
                    rec.decision = .selfExecute
                    let task = MustardTask(title: rec.title); task.notes = draftOrBody
                    context.insert(task)
                }
                .controlSize(.small)
                Spacer()
                Button("Reject", role: .destructive) { rec.decision = .denied }
                    .controlSize(.small)
            }
        }
    }

    private func eveningOrSoon() -> Date {
        let target = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
        return max(target, .now.addingTimeInterval(60))
    }
    private func tomorrow9() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors; an "unused" note is fine — it's wired in Task 3).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/RecommendationDetailView.swift
git commit -m "feat(agent-recs): standalone RecommendationDetailView (triage workspace)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Slim `RecommendationRow` + restructure `AgentConsoleView`

Both edits live in `Sources/MustardKit/Views/AgentConsoleView.swift` and are mutually dependent (the row's new init and the console's master-detail wiring), so they ship together and the build is verified once at the end.

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift`

- [ ] **Step 1: Replace `RecommendationRow` with the compact, selectable summary**

Replace the entire `struct RecommendationRow: View { … }` (currently lines 196–395, from the doc-comment `/// Rich triage card:` through its closing brace before `/// Provenance pill`) with:

```swift
/// Compact, selectable summary row for the recommendations master list. The full
/// triage workspace lives in `RecommendationDetailView` (the detail pane).
struct RecommendationRow: View {
    let rec: Recommendation
    let inGroup: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    init(rec: Recommendation, inGroup: Bool = false, isSelected: Bool = false, onSelect: @escaping () -> Void = {}) {
        self.rec = rec
        self.inGroup = inGroup
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    private var confidenceSegments: Int { Int((rec.confidence * 5).rounded(.down)) }
    private var confidenceColor: Color {
        rec.confidence >= 0.7 ? Theme.Palette.done
            : rec.confidence >= 0.4 ? Color(hex: "#BA7517") : Color(hex: "#D85A30")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inGroup { ProvenancePill(rec: rec) }
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.Palette.agent)
                Text(rec.title).font(Theme.Fonts.title).foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                if rec.action.isGated {
                    Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                        .help("Email, Slack, and ticket actions are always gated regardless of trust.")
                }
                Spacer()
                SourceLinkButton(rec: rec)
            }
            HStack(spacing: 6) {
                Text(String(format: "%.2f", rec.confidence))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(confidenceColor)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < confidenceSegments ? confidenceColor : Theme.Palette.surface)
                            .frame(width: 14, height: 4)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(isSelected ? Theme.Palette.accent.opacity(0.07) : .clear)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Theme.Palette.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
```

- [ ] **Step 2: Add state + environment to `AgentConsoleView`**

In `AgentConsoleView`, immediately after the existing `@AppStorage("trustLevel") private var trustRaw = …` line (currently line 12), add:

```swift
    @AppStorage("autoOpenSourceOnSelect") private var autoOpenSource = true
    @Environment(SourcePanelController.self) private var sourcePanel
    @State private var selected: Recommendation?
```

- [ ] **Step 3: Replace the `body` with the master-detail split**

Replace `AgentConsoleView`'s `body` (currently lines 28–74, `public var body: some View { ScrollView { … } .background(Theme.Palette.bg) }`) with:

```swift
    public var body: some View {
        HSplitView {
            masterColumn
                .frame(minWidth: 360, idealWidth: 480)
            detailColumn
                .frame(minWidth: 320, idealWidth: 420)
        }
        .background(Theme.Palette.bg)
        .onAppear {
            if selected == nil {
                selected = RecommendationSelection.nextSelection(current: nil, pending: pending)
            }
        }
        .onChange(of: pending.map(\.persistentModelID)) { _, _ in
            let next = RecommendationSelection.nextSelection(current: selected, pending: pending)
            if next !== selected { selected = next }
        }
    }

    private var masterColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                sourceRow
                meetingSourceRow
                SourceSettingsView()
                if let error = agent.lastError {
                    Text(error)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Color(hex: "#D85A30"))
                        .padding(.vertical, 8)
                }

                sectionLabel("RECOMMENDATIONS", count: pending.count)
                if pending.isEmpty {
                    emptyLine("Nothing waiting on you. Run a sweep.")
                }
                ForEach(SourceGrouping.grouped(pending)) { group in
                    if group.isMultiSource {
                        SourceGroupHeader(rec: group.header)
                        ForEach(group.members) { rec in
                            RecommendationRow(rec: rec, inGroup: true,
                                              isSelected: selected === rec,
                                              onSelect: { select(rec) })
                            Divider().overlay(Theme.Palette.hairline)
                        }
                    } else {
                        RecommendationRow(rec: group.header, inGroup: false,
                                          isSelected: selected === group.header,
                                          onSelect: { select(group.header) })
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }

                sectionLabel("REVIEW", count: reviewQueue.count)
                if reviewQueue.isEmpty {
                    emptyLine("No output waiting for review.")
                }
                ForEach(reviewQueue) { card in
                    OutputCardRow(card: card)
                    Divider().overlay(Theme.Palette.hairline)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    private var detailColumn: some View {
        Group {
            if let selected {
                ScrollView { RecommendationDetailView(rec: selected).padding(20) }
            } else {
                detailEmpty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.bg)
    }

    private var detailEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Theme.Palette.textTertiary)
            Text(pending.isEmpty ? "Nothing waiting on you." : "Select a recommendation.")
                .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Select a recommendation and, only on this explicit selection, auto-open its
    /// source if the setting is on and it has a web source. Programmatic re-selection
    /// (arrival / queue churn) does not auto-open — avoids surprise page loads.
    private func select(_ rec: Recommendation?) {
        selected = rec
        guard let rec,
              RecommendationSelection.shouldAutoOpenSource(settingOn: autoOpenSource, rec: rec),
              let link = SourceLink(from: rec) else { return }
        sourcePanel.open(link)
    }
```

- [ ] **Step 4: Add the auto-open toggle to the header**

Replace the existing `header` computed property (currently lines 76–90) with:

```swift
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agent")
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Palette.textPrimary)
            if agent.isExecuting {
                ProgressView().controlSize(.small)
                Text("working…")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Toggle(isOn: $autoOpenSource) {
                Text("Auto-open source").font(Theme.Fonts.meta)
            }
            .toggleStyle(.switch).controlSize(.mini)
            .help("When on, selecting a recommendation that has a source also opens it in the side panel.")
        }
        .padding(.bottom, 12)
    }
```

- [ ] **Step 5: Verify it builds**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(agent-recs): master-detail recommendations + auto-open-source toggle" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Full verification

- [ ] **Step 1: Run the whole suite**

Run: `swift test`
Expected: PASS — the prior suite plus the new `RecommendationSelectionTests` (8). 0 failures.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Manual confirmation (Leon)** — views are build + eye:

```bash
./build-app.sh && open build/Mustard.app
```

Check on the Agent tab:
- Recommendations show as a compact list on the left; the first pending rec is auto-selected and its detail (draft, actions, etc.) shows on the right.
- Clicking a rec selects it (accent highlight + left bar) and its detail replaces the right pane. Approve / Snooze / Schedule / I'll do it / Reject / Comment all work from the detail.
- With **Auto-open source** on: selecting a rec that has a source also opens the source inspector beside the detail (Model B); selecting a sourceless rec leaves the source panel as-is. With it off: selecting never opens the source panel, but the row's source glyph and ⌘⇧S still do.
- Approving/rejecting the selected rec moves the selection to the next pending rec (or the empty state when none remain).
- The `REVIEW` (output cards) section is unchanged.

- [ ] **Step 4: (No commit)** — verification only.

---

## Self-review

**Spec coverage:**
- Decision 1 (master-detail replaces inline; Review button gone) → Task 3 (slim row has no `expanded`/`Review`; console is `list │ detail`).
- Decision 2 (Model B coexist) → detail pane is the middle column; the source `.inspector` (on `main` from #20) composes trailing.
- Decision 3 (setting "auto-open source on select", default on, Agent header) → `@AppStorage("autoOpenSourceOnSelect") = true` + header `Toggle` (Task 3 Steps 2, 4) + `select()` wiring.
- Decision 4 (sourceless selection leaves panel as-is) → `select()` only calls `sourcePanel.open` when `shouldAutoOpenSource` is true (Task 1 test `test_shouldAutoOpenSource_onWithoutSource`).
- Behavior: auto-select first (`onAppear`), selection churn (`onChange` → `nextSelection`), empty state (`detailEmpty`), detail content (RecommendationDetailView), REVIEW untouched → all covered.
- Testing: `RecommendationSelectionTests` covers the pure decisions; views build + eye → Task 4.

**Placeholder scan:** none — every code step is complete; every run step has a command + expected result.

**Type consistency:** `RecommendationSelection.nextSelection(current:pending:)` and `shouldAutoOpenSource(settingOn:rec:)` are used identically in Tasks 1 and 3. `RecommendationRow(rec:inGroup:isSelected:onSelect:)` (Task 3 Step 1) matches its call sites (Task 3 Step 3). `RecommendationDetailView(rec:)` (Task 2) matches its use in `detailColumn` (Task 3). `select(_:)`, `selected`, `autoOpenSource`, `sourcePanel` are defined (Step 2) and used consistently (Step 3). `SourceLink(from:)` and `SourcePanelController.open(_:)` match the merged source-panel API.
