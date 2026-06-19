# Triage Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the agent triage loop honest about email — inert FYIs, a curated knowledge base, true Gmail provenance, the original email inline, and one email fanning out into several independently-triaged actions.

**Architecture:** Three sequenced features over the existing SwiftData + `claude -p` agent loop. New behaviour goes in PURE, unit-tested units (`Logic/`, `Agent` helpers); `AgentService` gains small action-aware branches; views only render and dispatch. No new `@Model` (fan-out display is Option A — a grouping *view* over recs that share `sourceItemID`). One additive optional field (`originalSource`), CloudKit-safe per ADR-0001.

**Tech Stack:** Swift / SwiftUI / SwiftData, XCTest, `swift build` + `swift test`. macOS 14+. SPM package (`MustardKit` lib + `Mustard` exe).

**Spec:** `docs/specs/2026-06-19-triage-provenance-fyi-and-fanout-design.md`

---

## File Structure

**New files:**
- `Sources/MustardKit/Logic/InboxLog.swift` — pure formatter + path for the curated KB rolling log.
- `Sources/MustardKit/Logic/SourceBadge.swift` — pure `SourceID → (icon, label, quiet?)` mapping for the provenance pill.
- `Sources/MustardKit/Logic/SourceGrouping.swift` — pure `[Recommendation] → [RecGroup]` for Option-A fan-out grouping.
- `Tests/MustardTests/InboxLogTests.swift`, `SourceBadgeTests.swift`, `SourceGroupingTests.swift`.

**Modified files:**
- `Sources/MustardKit/Models/Recommendation.swift` — add `originalSource: String?`.
- `Sources/MustardKit/Agent/SourceProposal.swift` — add `originalSource: String?` (Codable).
- `Sources/MustardKit/Agent/AgentService.swift` — `keep(_:)`; `.fyi` never executes; `create_task` → `MustardTask`; keep manual + trust paths consistent.
- `Sources/MustardKit/Agent/VaultSweep.swift` — sweep prompt ignores `_filed/`, `_recs/`, `.obsidian/`.
- `Sources/MustardKit/Views/AgentConsoleView.swift` — Keep/Dismiss for `.fyi`; source-grouped rendering; provenance pill; collapsible "Original email".
- `Tests/MustardTests/AgentTests.swift`, `RecommendationProvenanceTests.swift`, `SourceProposalTests.swift` — extend.

**Commit convention:** `type(scope): summary`, and end every commit message with a second `-m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`. Branch: `feat/triage-provenance-fyi-fanout` (already cut; the spec is committed there).

**Verification commands:** `swift test --filter <SuiteName>` per task; `swift build` after view tasks (CLAUDE.md: views are verified by build + eye, not unit tests — never claim a view "looks right", state it builds and ask Leon to confirm).

---

## Phase 1 — Inert FYI + curated-KB log writer

### Task 1: Add `originalSource` to the model + proposal

**Files:**
- Modify: `Sources/MustardKit/Models/Recommendation.swift`
- Modify: `Sources/MustardKit/Agent/SourceProposal.swift`
- Test: `Tests/MustardTests/RecommendationProvenanceTests.swift`, `Tests/MustardTests/SourceProposalTests.swift`

- [ ] **Step 1: Write the failing tests**

In `RecommendationProvenanceTests.swift`, add inside the class:

```swift
    func test_originalSource_defaultNil() {
        XCTAssertNil(Recommendation(title: "x").originalSource)
    }

    func test_originalSource_roundTrip() throws {
        let ctx = try makeContext()
        let rec = Recommendation(title: "From email", source: "gmail")
        rec.originalSource = "Hi Leon — for Monday's workshop…"
        ctx.insert(rec)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Recommendation>()).first?.originalSource,
                       "Hi Leon — for Monday's workshop…")
    }
```

In `SourceProposalTests.swift`, add inside the class:

```swift
    func test_sourceProposal_carriesOriginalSource_roundTrip() throws {
        let p = SourceProposal(source: .gmail, project: "DL", sourceItemID: "t", sourceEventID: "e",
                               title: "x", actionType: "fyi", originalSource: "raw email body")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateEncodingStrategy = .iso8601
        let back = try dec.decode(SourceProposal.self, from: enc.encode(p))
        XCTAssertEqual(back.originalSource, "raw email body")
        XCTAssertEqual(p, back)
    }

    func test_sourceProposal_decodesWhenOriginalSourceAbsent() throws {
        let json = #"{"source":"gmail","project":"DL","sourceItemID":"t","sourceEventID":"e","title":"x","actionType":"fyi","confidence":0.5,"reasoning":"","draft":""}"#
        let p = try JSONDecoder().decode(SourceProposal.self, from: Data(json.utf8))
        XCTAssertNil(p.originalSource)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RecommendationProvenanceTests --filter SourceProposalTests`
Expected: FAIL — `originalSource` is not a member of `Recommendation` / `SourceProposal`.

- [ ] **Step 3: Add the field to `Recommendation`**

In `Recommendation.swift`, after `public var sourceURL: String?` (line ~29):

```swift
    /// Raw source content (e.g. the original email body) so it can be read before the
    /// proposed draft. Optional → CloudKit-safe default (ADR-0001); vault recs leave it nil.
    public var originalSource: String?
```

In the `convenience init(from p: SourceProposal, vaultPath:)`, after `self.occurredAt = p.occurredAt`:

```swift
        self.originalSource = p.originalSource
```

- [ ] **Step 4: Add the field to `SourceProposal`**

In `SourceProposal.swift`, add a stored property after `public let sourceURL: String?`:

```swift
    public let originalSource: String?
```

Add the parameter to the designated `init` (give it a default so `init(vault:)` keeps compiling) — add `originalSource: String? = nil,` to the signature (e.g. right before `title:`) and `self.originalSource = originalSource` in the body.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter RecommendationProvenanceTests --filter SourceProposalTests`
Expected: PASS (existing `test_sourceProposal_codableRoundTrip` / `test_sourceProposal_decodesFromRoutineJSON` still pass — the new field is optional).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Models/Recommendation.swift Sources/MustardKit/Agent/SourceProposal.swift Tests/MustardTests/RecommendationProvenanceTests.swift Tests/MustardTests/SourceProposalTests.swift
git commit -m "feat(model): carry originalSource through proposal → recommendation" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `InboxLog` — pure rolling-log formatter

**Files:**
- Create: `Sources/MustardKit/Logic/InboxLog.swift`
- Test: `Tests/MustardTests/InboxLogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/InboxLogTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class InboxLogTests: XCTestCase {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func test_logURL_isUnderFiledFolder() {
        let url = InboxLog.logURL(workingDirectory: "/kb/DL")
        XCTAssertTrue(url.path.hasSuffix("/kb/DL/_filed/inbox-log.md"))
    }

    func test_entry_isDeterministic_withThreadLink() {
        let entry = InboxLog.entry(
            title: "Reply to Ruby", body: "be aware", source: "gmail",
            sourceURL: "https://x", now: utc(2026, 6, 19, 14, 32)
        )
        let expected =
            "## 2026-06-19 14:32 · gmail · Reply to Ruby\n" +
            "[thread](https://x)\n" +
            "\n" +
            "be aware\n" +
            "\n" +
            "---\n"
        XCTAssertEqual(entry, expected)
    }

    func test_entry_omitsThreadLine_whenNoURL() {
        let entry = InboxLog.entry(
            title: "Note", body: "body", source: "vault",
            sourceURL: nil, now: utc(2026, 6, 19, 9, 5)
        )
        XCTAssertFalse(entry.contains("[thread]"))
        XCTAssertTrue(entry.hasPrefix("## 2026-06-19 09:05 · vault · Note\n"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InboxLogTests`
Expected: FAIL — no such type `InboxLog`.

- [ ] **Step 3: Implement `InboxLog`**

Create `Sources/MustardKit/Logic/InboxLog.swift`:

```swift
import Foundation

/// Pure formatting + pathing for the curated-KB rolling log (the "Keep" target).
/// The actual append is a thin side effect in `AgentService`; content and path live
/// here so they stay unit-tested (CLAUDE.md: logic is TDD; pin time/timezone).
public enum InboxLog {
    /// `<workingDirectory>/_filed/inbox-log.md` — one rolling log per project. The
    /// `_filed/` folder is excluded from the vault sweep, so kept notes never loop back.
    public static func logURL(workingDirectory: String) -> URL {
        URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("_filed")
            .appendingPathComponent("inbox-log.md")
    }

    /// One markdown entry for a kept recommendation.
    public static func entry(
        title: String, body: String, source: String, sourceURL: String?, now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) -> String {
        var cal = calendar
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let stamp = String(format: "%04d-%02d-%02d %02d:%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let label = source.isEmpty ? "note" : source
        var lines = ["## \(stamp) · \(label) · \(title)"]
        if let url = sourceURL, !url.isEmpty { lines.append("[thread](\(url))") }
        lines.append(contentsOf: ["", body, "", "---", ""])
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InboxLogTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/InboxLog.swift Tests/MustardTests/InboxLogTests.swift
git commit -m "feat(logic): InboxLog rolling-log formatter for curated KB" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `AgentService.keep` + `.fyi` never executes

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift` (`decide` ~145-150; add `keep`)
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the failing tests**

In `AgentTests.swift`, add inside `AgentServiceTests`:

```swift
    func test_decide_approved_fyi_doesNotExecute() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "FYI", actionType: "fyi", vaultPath: "/v")
        ctx.insert(rec)

        await service.decide(rec, .approved)

        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }

    func test_keep_fyi_appendsLog_noClaude_noCard() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rec = Recommendation(title: "Standup moved", body: "now 9:30", actionType: "fyi", vaultPath: dir.path)
        ctx.insert(rec)

        service.keep(rec)

        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
        XCTAssertEqual(rec.decision, .approved)
        let log = try String(contentsOf: InboxLog.logURL(workingDirectory: dir.path), encoding: .utf8)
        XCTAssertTrue(log.contains("Standup moved"))
        XCTAssertTrue(log.contains("now 9:30"))
    }

    func test_keep_appends_doesNotClobberExisting() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = Recommendation(title: "First", actionType: "fyi", vaultPath: dir.path)
        let b = Recommendation(title: "Second", actionType: "fyi", vaultPath: dir.path)
        ctx.insert(a); ctx.insert(b)

        service.keep(a); service.keep(b)

        let log = try String(contentsOf: InboxLog.logURL(workingDirectory: dir.path), encoding: .utf8)
        XCTAssertTrue(log.contains("First"))
        XCTAssertTrue(log.contains("Second"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentServiceTests`
Expected: FAIL — `keep` is undefined; `decide(.approved)` on a `.fyi` currently executes (stub called).

- [ ] **Step 3: Add the `.fyi` guard to `decide`**

In `AgentService.swift`, replace the body of `decide`:

```swift
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        guard decision == .approved else { return }
        if rec.action == .fyi { return }   // acknowledging an FYI runs nothing
        _ = await execute(rec, feedback: rec.comment)
    }
```

- [ ] **Step 4: Add `keep`**

In `AgentService.swift`, after `comment(_:_:)`:

```swift
    /// Keep an FYI: append it to the project's curated rolling log and clear it from the
    /// queue. No claude run, no OutputCard — filing is a direct local write.
    public func keep(_ rec: Recommendation) {
        let entry = InboxLog.entry(
            title: rec.title, body: rec.originalSource ?? rec.body,
            source: rec.source, sourceURL: rec.sourceURL, now: .now
        )
        let url = InboxLog.logURL(workingDirectory: rec.vaultPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + entry).write(to: url, atomically: true, encoding: .utf8)
        rec.decision = .approved
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AgentServiceTests`
Expected: PASS (existing approve/execute/trust tests use `vault_note` / `draft_email`, so they're unaffected).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): inert FYI — keep files to KB log, approve never runs claude" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: FYI shows Keep / Dismiss (view)

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift` (`RecommendationRow.outcomes` ~279-323)

View task — no unit test (CLAUDE.md: views are build + eye).

- [ ] **Step 1: Make the outcome row action-aware**

In `RecommendationRow`, replace the `outcomes` view so `.fyi` recs show Keep/Dismiss (re-bucket still reachable via Review), and all other actions keep today's buttons. Add at the top of `outcomes`'s `HStack`:

```swift
        if rec.action == .fyi {
            Button("Keep") { agent.keep(rec) }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.accent)
                .controlSize(.small)
                .help("File this to your knowledge base log, then clear it.")
            Button(expanded ? "Hide" : "Review") {
                withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
            }
            .controlSize(.small)
            Spacer()
            Button("Dismiss", role: .destructive) { rec.decision = .denied }
                .controlSize(.small)
                .help("You've seen it — remove it. Nothing is stored.")
        } else {
            // existing Approve / Review / Comment / Snooze / Schedule / I'll do it / Reject
        }
```

Move the current contents of `outcomes` into the `else` branch verbatim.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Eye-check + commit**

Run the app (`./build-app.sh && open build/Mustard.app`), confirm an FYI rec shows **Keep / Review / Dismiss** and a non-FYI shows the full button row. State it builds and runs; ask Leon to confirm the look. Then:

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(ui): FYI rows show Keep / Dismiss instead of Approve / Reject" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — Curated KB sweep guard

### Task 5: Vault sweep ignores `_filed/`, `_recs/`, `.obsidian/`

**Files:**
- Modify: `Sources/MustardKit/Agent/VaultSweep.swift` (`prompt` ~5-20)
- Test: `Tests/MustardTests/AgentTests.swift` (in `VaultSweepPromptTests`)

> Operational prerequisite (Leon, no code): disable the external email→KB-note routine so emails arrive only as `gmail` recs via `_recs/`.

- [ ] **Step 1: Write the failing test**

In `AgentTests.swift`, add inside `VaultSweepPromptTests`:

```swift
    func test_prompt_ignoresAppInternalFolders() {
        XCTAssertTrue(VaultSweep.prompt.contains("_filed/"))
        XCTAssertTrue(VaultSweep.prompt.contains("_recs/"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VaultSweepPromptTests`
Expected: FAIL — prompt has no ignore line.

- [ ] **Step 3: Add the ignore line to the sweep prompt**

In `VaultSweep.swift`, insert into the `prompt` string after the "Look at the notes…" line:

```
    Ignore these app-internal folders entirely — never read or propose from them:
    `_filed/` (your own filed log), `_recs/` (the email scout's drop folder), `.obsidian/`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VaultSweepPromptTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/VaultSweep.swift Tests/MustardTests/AgentTests.swift
git commit -m "fix(sweep): ignore _filed/ and _recs/ so kept notes never loop back" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 3 — Email source + fan-out (Option A)

### Task 6: `SourceBadge` — provenance display mapping

**Files:**
- Create: `Sources/MustardKit/Logic/SourceBadge.swift`
- Test: `Tests/MustardTests/SourceBadgeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/SourceBadgeTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class SourceBadgeTests: XCTestCase {
    func test_gmail_isBadged() {
        let b = SourceBadge.badge(for: .gmail)
        XCTAssertFalse(b.isQuiet)
        XCTAssertEqual(b.label, "Gmail")
    }

    func test_vault_isQuiet() {
        XCTAssertTrue(SourceBadge.badge(for: .vault).isQuiet)
    }

    func test_unknownRaw_fallsBackToQuietVault() {
        XCTAssertTrue(SourceBadge.badge(forRaw: "carrier-pigeon").isQuiet)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceBadgeTests`
Expected: FAIL — no `SourceBadge`.

- [ ] **Step 3: Implement `SourceBadge`**

Create `Sources/MustardKit/Logic/SourceBadge.swift`:

```swift
import Foundation

/// Pure mapping from a source to how the triage UI badges it. Vault stays quiet (plain
/// text line, no pill); non-vault sources get an icon + label. Keeps the view dumb.
public struct SourceBadge: Equatable {
    public let symbol: String   // SF Symbol name
    public let label: String
    public let isQuiet: Bool     // vault → true: no pill, matches today's calm look

    public static func badge(for source: SourceID) -> SourceBadge {
        switch source {
        case .gmail: SourceBadge(symbol: "envelope.fill", label: "Gmail", isQuiet: false)
        case .vault: SourceBadge(symbol: "books.vertical", label: "Vault", isQuiet: true)
        }
    }

    /// Tolerant entry point for the stored `Recommendation.source` string.
    public static func badge(forRaw raw: String) -> SourceBadge {
        badge(for: SourceID(rawValue: raw) ?? .vault)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SourceBadgeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/SourceBadge.swift Tests/MustardTests/SourceBadgeTests.swift
git commit -m "feat(logic): SourceBadge maps source → provenance pill (vault quiet)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: `SourceGrouping` — fan-out grouping (Option A)

**Files:**
- Create: `Sources/MustardKit/Logic/SourceGrouping.swift`
- Test: `Tests/MustardTests/SourceGroupingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/SourceGroupingTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class SourceGroupingTests: XCTestCase {
    private func rec(_ title: String, item: String?) -> Recommendation {
        let r = Recommendation(title: title)
        r.sourceItemID = item
        return r
    }

    func test_sharedSourceItemID_groupsTogether() {
        let groups = SourceGrouping.grouped([
            rec("Reply to Ruby", item: "thread-1"),
            rec("Find answers", item: "thread-1"),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isMultiSource)
        XCTAssertEqual(groups[0].members.map(\.title), ["Reply to Ruby", "Find answers"])
    }

    func test_distinctSourceItemID_areSeparateSingletons() {
        let groups = SourceGrouping.grouped([
            rec("A", item: "thread-1"),
            rec("B", item: "thread-2"),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertFalse(groups[0].isMultiSource)
        XCTAssertFalse(groups[1].isMultiSource)
    }

    func test_nilSourceItemID_neverGroups() {
        let groups = SourceGrouping.grouped([rec("A", item: nil), rec("B", item: nil)])
        XCTAssertEqual(groups.count, 2)
    }

    func test_preservesFirstAppearanceOrder() {
        let groups = SourceGrouping.grouped([
            rec("first", item: "t1"),
            rec("second", item: "t2"),
            rec("first-again", item: "t1"),
        ])
        XCTAssertEqual(groups.map(\.id), ["t1", "t2"])
        XCTAssertEqual(groups[0].members.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceGroupingTests`
Expected: FAIL — no `SourceGrouping` / `RecGroup`.

- [ ] **Step 3: Implement `SourceGrouping`**

Create `Sources/MustardKit/Logic/SourceGrouping.swift`:

```swift
import Foundation

/// A provenance header plus the recommendations that share one source item (e.g. one
/// email thread). Option A: grouping is a *view* over recs — no persisted entity.
public struct RecGroup: Identifiable {
    public let id: String
    public let members: [Recommendation]
    /// True when one source produced several recs → render the shared header + fan-out.
    public var isMultiSource: Bool { members.count > 1 }
    /// Provenance comes from any member (they share the source).
    public var header: Recommendation { members[0] }
}

public enum SourceGrouping {
    /// Group recs so multiple recs from one source render under a single header. Recs
    /// with a shared non-empty `sourceItemID` group together; everything else is a
    /// singleton. First-appearance order is preserved.
    public static func grouped(_ recs: [Recommendation]) -> [RecGroup] {
        var order: [String] = []
        var buckets: [String: [Recommendation]] = [:]
        for (i, rec) in recs.enumerated() {
            let key = (rec.sourceItemID?.isEmpty == false) ? rec.sourceItemID! : "solo-\(i)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(rec)
        }
        return order.map { RecGroup(id: $0, members: buckets[$0] ?? []) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SourceGroupingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/SourceGrouping.swift Tests/MustardTests/SourceGroupingTests.swift
git commit -m "feat(logic): SourceGrouping groups recs by source item (fan-out)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: `create_task` approval lands a real `MustardTask`

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift` (`decide`; `applyTrust` ~115-131; add `materializeTask`)
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the failing tests**

In `AgentTests.swift`, add inside `AgentServiceTests`:

```swift
    func test_approve_createTask_insertsInboxTask_noClaude_noCard() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Find Ruby's error screens", actionType: "create_task",
                                 vaultPath: "/v", draft: "Locate in Figma; answer Liam's Qs")
        ctx.insert(rec)

        await service.decide(rec, .approved)

        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
        let tasks = try ctx.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Find Ruby's error screens")
        XCTAssertEqual(tasks.first?.notes, "Locate in Figma; answer Liam's Qs")
        XCTAssertEqual(tasks.first?.status, .inbox)
    }

    func test_applyTrust_createTask_insertsTask_notCard() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Do the thing", actionType: "create_task", vaultPath: "/v", confidence: 0.9)
        ctx.insert(rec)

        await service.applyTrust(.trusted)

        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MustardTask>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }

    func test_applyTrust_skipsFyi() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Heads up", actionType: "fyi", vaultPath: "/v", confidence: 0.9)
        ctx.insert(rec)

        await service.applyTrust(.autonomous)

        XCTAssertFalse(called)
        XCTAssertEqual(rec.decision, .pending)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentServiceTests`
Expected: FAIL — `create_task` approve currently executes (card, no task); `applyTrust` executes both.

- [ ] **Step 3: Add `materializeTask` and branch `decide`**

In `AgentService.swift`, add after `keep(_:)`:

```swift
    /// Approving a create_task lands a real task in the inbox — no claude run, no
    /// OutputCard. The task appearing is the confirmation (mirrors the "I'll do it" button).
    private func materializeTask(from rec: Recommendation) {
        let task = MustardTask(title: rec.title)
        task.notes = rec.draft.isEmpty ? rec.body : rec.draft
        task.status = .inbox
        context.insert(task)
    }
```

Update `decide` (insert the create_task branch after the `.fyi` guard):

```swift
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        guard decision == .approved else { return }
        if rec.action == .fyi { return }
        if rec.action == .createTask { materializeTask(from: rec); return }
        _ = await execute(rec, feedback: rec.comment)
    }
```

- [ ] **Step 4: Make `applyTrust` consistent**

In `AgentService.swift`, replace the `for rec in pending` loop body in `applyTrust`:

```swift
        for rec in pending {
            if rec.action == .fyi { continue }   // awareness items are never auto-actioned
            guard TrustPolicy.shouldAutoApprove(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) else { continue }
            rec.decision = .approved
            if rec.action == .createTask { materializeTask(from: rec); continue }
            let card = await execute(rec)
            if let card, TrustPolicy.shouldAutoAccept(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) {
                card.review = .accepted
            }
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AgentServiceTests`
Expected: PASS (existing trust tests use `vault_note`, unaffected).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): approving create_task inserts a real inbox task" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Console — source grouping, provenance pill, original email (view)

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift` (pending list ~46-49; `provenanceLine` ~209-222; `drawer` ~245-277)

View task — no unit test; the logic it consumes (`SourceGrouping`, `SourceBadge`) is already tested. Verify with `swift build` + Leon's eye.

- [ ] **Step 1: Render pending recs grouped**

Replace the pending `ForEach` in `AgentConsoleView.body`:

```swift
                ForEach(SourceGrouping.grouped(pending)) { group in
                    if group.isMultiSource {
                        SourceGroupHeader(rec: group.header)
                        ForEach(group.members) { rec in
                            RecommendationRow(rec: rec, inGroup: true)
                            Divider().overlay(Theme.Palette.hairline)
                        }
                    } else {
                        RecommendationRow(rec: group.header, inGroup: false)
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }
```

- [ ] **Step 2: Add the group header + provenance pill**

Add a `SourceGroupHeader` view and a shared `ProvenancePill`, and give `RecommendationRow` an `inGroup` flag (default false) that suppresses its own provenance line when it's under a group header:

```swift
struct ProvenancePill: View {
    let rec: Recommendation
    var body: some View {
        let badge = SourceBadge.badge(forRaw: rec.source)
        HStack(spacing: 6) {
            if badge.isQuiet {
                Text(badge.label.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                Label(badge.label, systemImage: badge.symbol)
                    .labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#A32D2D"))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(hex: "#FCEBEB"), in: Capsule())
            }
            if !rec.sourceContext.isEmpty {
                Text("· \(rec.sourceContext)").font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer()
            if let s = rec.sourceURL, let url = URL(string: s) {
                Link("Open ↗", destination: url).font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

struct SourceGroupHeader: View {
    let rec: Recommendation
    @State private var showEmail = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProvenancePill(rec: rec)
            if let original = rec.originalSource, !original.isEmpty {
                Button { withAnimation(.snappy(duration: 0.15)) { showEmail.toggle() } } label: {
                    Label(showEmail ? "Hide original" : "Original email",
                          systemImage: showEmail ? "chevron.down" : "chevron.right")
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary)
                }.buttonStyle(.plain)
                if showEmail {
                    Text(original).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                        .textSelection(.enabled)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.hairline).frame(width: 1) }
                }
            }
        }
        .padding(.top, 6).padding(.bottom, 2)
    }
}
```

In `RecommendationRow`, add the stored `let inGroup: Bool` (with a memberwise init `init(rec:, inGroup: Bool = false)`), and in `body` render `provenanceLine` only when `!inGroup` (the group header already shows it). Replace the inline `provenanceLine` contents to use `ProvenancePill(rec: rec)` so single recs get the pill too.

- [ ] **Step 3: Add the original-email peek to the single-rec drawer**

In `RecommendationRow.drawer`, above the `PROPOSED DRAFT` block, add:

```swift
        if let original = rec.originalSource, !original.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ORIGINAL EMAIL").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(original).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: build succeeds. Fix any signature mismatch (e.g. `RecommendationRow(rec:inGroup:)` call sites).

- [ ] **Step 5: Eye-check + commit**

Run the app and confirm: a Gmail rec shows the Gmail pill + collapsible original email; two recs from one thread render under one header; vault recs stay quiet. State it builds and runs; ask Leon to confirm. Then:

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(ui): source-grouped triage with provenance pill + original email" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Whole suite green:** `swift test` — expect all suites pass (was 73 cases + the new ones).
- [ ] **Build clean:** `swift build`.
- [ ] **App smoke test:** `./build-app.sh && open build/Mustard.app` — sweep a vault, confirm FYI Keep/Dismiss, a fanned-out Gmail item (once the scout emits it), and create_task landing a real inbox task. Ask Leon to confirm the surfaces.

## Out of scope (do not build)

- Option B `SourceItem` persisted entity.
- Sending email/Slack/tickets — still draft-only.
- Auto-fan-out heuristics beyond what the scout prompt emits (the scout-prompt change to emit multiple recs + `originalSource` is tracked in `docs/scout-routine-prompt.md`, edited outside this Swift package).
- Trust × FYI auto-keep semantics (FYI is deliberately never auto-actioned here).

## Scout-side follow-up (not in this package)

For the fan-out and original email to actually appear, `docs/scout-routine-prompt.md` must change to: (a) include the raw email body as `originalSource`, and (b) emit multiple `_recs/*.json` for one email when it implies several actions (e.g. `draft_email` reply + `create_task`), sharing `sourceItemID` (the thread id) with distinct `sourceEventID`. This is a prompt edit, not Swift — flagged here so it isn't missed.
