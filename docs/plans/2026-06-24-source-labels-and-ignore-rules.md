# Source labelling, Ignore-vanish & ticket/task bucketing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Badge Jira/Shortcut recs with their own source pill (replacing Gmail), auto-ignore + hide Shortcut "PO Review" assignments and all `ignore` recs, and refine the classifier prompts to separate "draft a new ticket" from "act on an existing one".

**Architecture:** All deterministic rules are pure units in `Logic/`, applied in the shared `ingest()` pipeline ([AgentService.swift:111](../../Sources/MustardKit/Agent/AgentService.swift)) so they cover vault + Gmail recs uniformly. The triage-queue filter is extracted to a pure helper so the "hide ignore" rule is unit-tested. Views only render. Feature 3 is prompt text (no behavioural test; Leon re-pastes the scout prompt into his local routine).

**Tech Stack:** Swift Package (SwiftUI + SwiftData), XCTest. `swift test` / `swift build`. Spec: [docs/specs/2026-06-24-source-labels-ignore-and-bucketing-design.md](../specs/2026-06-24-source-labels-ignore-and-bucketing-design.md).

---

## File structure

| File | Responsibility |
|------|----------------|
| `Sources/MustardKit/Agent/SourceProposal.swift` | `SourceID` += jira/shortcut; `reclassified()` copy helper (modify) |
| `Sources/MustardKit/Logic/SourceClassifier.swift` | **new** — transport + context → logical source (pure) |
| `Sources/MustardKit/Logic/IngestNormalizer.swift` | **new** — compose source reclassify + PO-review→ignore (pure) |
| `Sources/MustardKit/Logic/RecommendationQueue.swift` | **new** — pure pending filter (drops ignore + snoozed) |
| `Sources/MustardKit/Logic/SourceBadge.swift` | colour hexes + jira/shortcut badges (modify) |
| `Sources/MustardKit/Agent/AgentService.swift` | `ingest()` normalizes; `applyTrust` skips ignore (modify) |
| `Sources/MustardKit/Views/AgentConsoleView.swift` | `pending` uses helper; `ProvenancePill` uses badge colours (modify) |
| `Sources/MustardKit/Agent/VaultSweep.swift` | prompt: ticket_write vs create_task rule (modify) |
| `docs/scout-routine-prompt.md` | same rule for the Gmail scout (modify) |
| `Tests/MustardTests/*` | new: `SourceClassifierTests`, `IngestNormalizerTests`, `RecommendationQueueTests`; extend `SourceProposalTests`, `SourceBadgeTests`, `AgentTests` |

Dependency order: 1 → 2 → 3 (normalization core) → 4 (badge) → 5 (queue) → 6 (service wiring) → 7 (view wiring) → 8 (prompts) → 9 (integration + full suite).

---

## Task 1: `SourceID` cases + `reclassified()` helper

**Files:**
- Modify: `Sources/MustardKit/Agent/SourceProposal.swift`
- Test: `Tests/MustardTests/SourceProposalTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `SourceProposalTests` (before the closing `}`):

```swift
    func test_sourceID_jiraAndShortcut_rawValues() {
        XCTAssertEqual(SourceID(rawValue: "jira"), .jira)
        XCTAssertEqual(SourceID(rawValue: "shortcut"), .shortcut)
    }

    func test_reclassified_overridesSourceAndAction_preservesEverythingElse() {
        let p = SourceProposal(
            source: .gmail, project: "DL", sourceItemID: "t1", sourceEventID: "e1",
            sourceContext: "Jira · DLA-5280", sourceURL: "https://x", title: "T", body: "B",
            actionType: "ticket_write", originalSource: "raw", confidence: 0.8,
            reasoning: "r", draft: "d"
        )
        let out = p.reclassified(source: .jira, actionType: "create_task")
        XCTAssertEqual(out.source, .jira)
        XCTAssertEqual(out.actionType, "create_task")
        XCTAssertEqual(out.project, "DL")
        XCTAssertEqual(out.sourceItemID, "t1")
        XCTAssertEqual(out.sourceEventID, "e1")
        XCTAssertEqual(out.sourceContext, "Jira · DLA-5280")
        XCTAssertEqual(out.sourceURL, "https://x")
        XCTAssertEqual(out.title, "T")
        XCTAssertEqual(out.body, "B")
        XCTAssertEqual(out.originalSource, "raw")
        XCTAssertEqual(out.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(out.reasoning, "r")
        XCTAssertEqual(out.draft, "d")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SourceProposalTests`
Expected: FAIL to compile — `.jira`/`.shortcut` not members of `SourceID`; `reclassified` not a member.

- [ ] **Step 3: Add the enum cases**

In `Sources/MustardKit/Agent/SourceProposal.swift`, change the enum:

```swift
public enum SourceID: String, Codable, CaseIterable, Sendable {
    case gmail
    case vault
    case jira
    case shortcut
}
```

- [ ] **Step 4: Add the `reclassified` helper**

In the `public extension SourceProposal { … }` block (after `init(vault:project:)`), add:

```swift
    /// A copy with the logical source and/or action overridden, everything else
    /// preserved. Used by `IngestNormalizer` to re-stamp the immutable proposal.
    func reclassified(source: SourceID, actionType: String) -> SourceProposal {
        SourceProposal(
            source: source, project: project, sourceItemID: sourceItemID,
            sourceEventID: sourceEventID, sourceContext: sourceContext, sourceURL: sourceURL,
            occurredAt: occurredAt, title: title, body: body, actionType: actionType,
            originalSource: originalSource, confidence: confidence, reasoning: reasoning, draft: draft
        )
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SourceProposalTests`
Expected: PASS (all existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/SourceProposal.swift Tests/MustardTests/SourceProposalTests.swift
git commit -m "feat(source): add jira/shortcut SourceID + reclassified() copy helper" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `SourceClassifier` (pure)

**Files:**
- Create: `Sources/MustardKit/Logic/SourceClassifier.swift`
- Create: `Tests/MustardTests/SourceClassifierTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/SourceClassifierTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class SourceClassifierTests: XCTestCase {
    func test_gmailWithJiraLeadingToken_isJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Jira · DLA-5280 · mentioned"), .jira)
    }

    func test_gmailWithShortcutLeadingToken_isShortcut() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Shortcut · Digital Licence · sub-task"), .shortcut)
    }

    func test_gmailWithTicketKeyOnly_fallsBackToJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Mentioned on DLA-5280"), .jira)
    }

    func test_gmailUnrelatedContext_staysGmail() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "App Store Connect · SalesBuddi · app rejected"), .gmail)
    }

    func test_gmailEmptyContext_staysGmail() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: ""), .gmail)
    }

    func test_nonGmailTransport_isNeverReclassified() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .vault, sourceContext: "Jira · DLA-1"), .vault)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceClassifierTests`
Expected: FAIL to compile — no `SourceClassifier`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MustardKit/Logic/SourceClassifier.swift`:

```swift
import Foundation

/// Derives the *logical* source of a Gmail-delivered rec from its provenance text.
/// Jira/Shortcut notifications arrive over Gmail; the meaningful source is the system
/// the notification is about. Pure + tested. Only `gmail` is ever reclassified —
/// vault/delegated/already-classified transports pass through unchanged.
public enum SourceClassifier {
    public static func logicalSource(transport: SourceID, sourceContext: String) -> SourceID {
        guard transport == .gmail else { return transport }
        let ctx = sourceContext.trimmingCharacters(in: .whitespaces).lowercased()
        if ctx.hasPrefix("jira") { return .jira }
        if ctx.hasPrefix("shortcut") { return .shortcut }
        // Jira-style ticket key (e.g. DLA-5280) anywhere in the provenance → Jira.
        if sourceContext.range(of: #"[A-Z]{2,}-\d+"#, options: .regularExpression) != nil { return .jira }
        return .gmail
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SourceClassifierTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/SourceClassifier.swift Tests/MustardTests/SourceClassifierTests.swift
git commit -m "feat(source): SourceClassifier derives jira/shortcut from gmail provenance" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `IngestNormalizer` (pure — source reclassify + PO-review→ignore)

**Files:**
- Create: `Sources/MustardKit/Logic/IngestNormalizer.swift`
- Create: `Tests/MustardTests/IngestNormalizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/IngestNormalizerTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class IngestNormalizerTests: XCTestCase {
    private func proposal(source: SourceID, context: String, title: String, action: String) -> SourceProposal {
        SourceProposal(source: source, project: "DL", sourceItemID: "t", sourceEventID: "e",
                       sourceContext: context, title: title, actionType: action)
    }

    func test_shortcutPOReviewInTitle_demotesToIgnore() {
        let p = proposal(source: .gmail,
                         context: "Shortcut · Digital Licence · Tom added sub-task assigned to Leon",
                         title: "Complete PO Review sub-task (DLV Favourite Bundles)",
                         action: "create_task")
        let out = IngestNormalizer.normalize(p)
        XCTAssertEqual(out.source, .shortcut)
        XCTAssertEqual(out.actionType, "ignore")
    }

    func test_shortcutPOReviewInContext_demotesToIgnore() {
        let p = proposal(source: .gmail,
                         context: "Shortcut · Digital Licence · added sub-task 'PO Review' to Leon",
                         title: "Some other title", action: "vault_note")
        XCTAssertEqual(IngestNormalizer.normalize(p).actionType, "ignore")
    }

    func test_shortcutWithoutPOReview_keepsAction() {
        let p = proposal(source: .gmail, context: "Shortcut · Digital Licence · comment added",
                         title: "Reply to comment", action: "draft_email")
        let out = IngestNormalizer.normalize(p)
        XCTAssertEqual(out.source, .shortcut)
        XCTAssertEqual(out.actionType, "draft_email")
    }

    func test_jiraWithPOReviewWording_isNotIgnored() {
        // PO-review demotion is scoped to Shortcut; a Jira item is unaffected.
        let p = proposal(source: .gmail, context: "Jira · DLA-1 · PO Review mentioned",
                         title: "PO Review note", action: "create_task")
        let out = IngestNormalizer.normalize(p)
        XCTAssertEqual(out.source, .jira)
        XCTAssertEqual(out.actionType, "create_task")
    }

    func test_genericGmail_passesThroughUnchanged() {
        let p = proposal(source: .gmail, context: "App Store Connect · rejected",
                         title: "x", action: "fyi")
        let out = IngestNormalizer.normalize(p)
        XCTAssertEqual(out.source, .gmail)
        XCTAssertEqual(out.actionType, "fyi")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IngestNormalizerTests`
Expected: FAIL to compile — no `IngestNormalizer`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MustardKit/Logic/IngestNormalizer.swift`:

```swift
import Foundation

/// Deterministic Mac-side normalization applied to every ingested `SourceProposal`
/// before dedupe: derive the logical source (Jira/Shortcut over the Gmail transport)
/// and demote routine Shortcut "PO Review" assignments to `ignore`. Pure + tested.
public enum IngestNormalizer {
    public static func normalize(_ p: SourceProposal) -> SourceProposal {
        let source = SourceClassifier.logicalSource(transport: p.source, sourceContext: p.sourceContext)
        let action = demotesToIgnore(source: source, title: p.title, sourceContext: p.sourceContext)
            ? "ignore" : p.actionType
        return p.reclassified(source: source, actionType: action)
    }

    /// A Shortcut "PO Review" assignment is Leon's standing responsibility and needs no
    /// triage — demote it to `ignore`. Scoped to Shortcut so unrelated mentions are untouched.
    public static func demotesToIgnore(source: SourceID, title: String, sourceContext: String) -> Bool {
        guard source == .shortcut else { return false }
        return (title + " " + sourceContext).lowercased().contains("po review")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IngestNormalizerTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/IngestNormalizer.swift Tests/MustardTests/IngestNormalizerTests.swift
git commit -m "feat(ingest): IngestNormalizer reclassifies source + demotes PO-review to ignore" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `SourceBadge` colours + jira/shortcut badges

**Files:**
- Modify: `Sources/MustardKit/Logic/SourceBadge.swift`
- Test: `Tests/MustardTests/SourceBadgeTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `SourceBadgeTests` (before the closing `}`):

```swift
    func test_jira_badge() {
        let b = SourceBadge.badge(for: .jira)
        XCTAssertFalse(b.isQuiet)
        XCTAssertEqual(b.label, "Jira")
        XCTAssertEqual(b.symbol, "diamond.fill")
        XCTAssertEqual(b.fgHex, "#2E5CB8")
    }

    func test_shortcut_badge() {
        let b = SourceBadge.badge(for: .shortcut)
        XCTAssertFalse(b.isQuiet)
        XCTAssertEqual(b.label, "Shortcut")
        XCTAssertEqual(b.bgHex, "#ECE8F7")
    }

    func test_gmail_carriesItsColours() {
        let b = SourceBadge.badge(for: .gmail)
        XCTAssertEqual(b.fgHex, "#A32D2D")
        XCTAssertEqual(b.bgHex, "#FCEBEB")
    }

    func test_jira_fromRaw() {
        XCTAssertEqual(SourceBadge.badge(forRaw: "jira").label, "Jira")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SourceBadgeTests`
Expected: FAIL to compile — no `fgHex`/`bgHex`; no `.jira`/`.shortcut` badges.

- [ ] **Step 3: Write the implementation**

Replace the contents of `Sources/MustardKit/Logic/SourceBadge.swift` with:

```swift
import Foundation

/// Pure mapping from a source to how the triage UI badges it. Vault stays quiet (plain
/// text line, no pill); non-vault sources get an icon + label + their own pill colours.
/// Colours are hex strings (not SwiftUI `Color`) so this stays a pure Logic unit.
public struct SourceBadge: Equatable {
    public let symbol: String   // SF Symbol name
    public let label: String
    public let isQuiet: Bool     // vault → true: no pill, matches today's calm look
    public let fgHex: String     // pill text colour (unused when isQuiet)
    public let bgHex: String     // pill background (unused when isQuiet)

    public init(symbol: String, label: String, isQuiet: Bool, fgHex: String = "", bgHex: String = "") {
        self.symbol = symbol
        self.label = label
        self.isQuiet = isQuiet
        self.fgHex = fgHex
        self.bgHex = bgHex
    }

    public static func badge(for source: SourceID) -> SourceBadge {
        switch source {
        case .gmail: SourceBadge(symbol: "envelope.fill", label: "Gmail", isQuiet: false, fgHex: "#A32D2D", bgHex: "#FCEBEB")
        case .jira: SourceBadge(symbol: "diamond.fill", label: "Jira", isQuiet: false, fgHex: "#2E5CB8", bgHex: "#E7EEF9")
        case .shortcut: SourceBadge(symbol: "flag.fill", label: "Shortcut", isQuiet: false, fgHex: "#5B4AA8", bgHex: "#ECE8F7")
        case .vault: SourceBadge(symbol: "books.vertical", label: "Vault", isQuiet: true)
        }
    }

    /// Tolerant entry point for the stored `Recommendation.source` string.
    public static func badge(forRaw raw: String) -> SourceBadge {
        badge(for: SourceID(rawValue: raw) ?? .vault)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SourceBadgeTests`
Expected: PASS (existing 3 + new 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/SourceBadge.swift Tests/MustardTests/SourceBadgeTests.swift
git commit -m "feat(source): jira (blue) + shortcut (purple) badges with pill colours" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `RecommendationQueue` (pure pending filter)

**Files:**
- Create: `Sources/MustardKit/Logic/RecommendationQueue.swift`
- Create: `Tests/MustardTests/RecommendationQueueTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/RecommendationQueueTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class RecommendationQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func rec(action: String = "vault_note", decision: RecommendationDecision = .pending,
                     snooze: Date? = nil) -> Recommendation {
        let r = Recommendation(title: "x", actionType: action)
        r.decision = decision
        r.snoozedUntil = snooze
        return r
    }

    func test_excludesIgnore() {
        XCTAssertTrue(RecommendationQueue.pending([rec(action: "ignore")], now: now).isEmpty)
    }

    func test_keepsPendingVaultNoteAndFyi() {
        let recs = [rec(action: "vault_note"), rec(action: "fyi")]
        XCTAssertEqual(RecommendationQueue.pending(recs, now: now).count, 2)
    }

    func test_excludesFutureSnoozed_keepsDueSnoozed() {
        let future = rec(snooze: now.addingTimeInterval(3600))
        let due = rec(snooze: now.addingTimeInterval(-1))
        let out = RecommendationQueue.pending([future, due], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out.contains { $0 === due })
    }

    func test_excludesDecided() {
        let recs = [rec(decision: .approved), rec(decision: .denied)]
        XCTAssertTrue(RecommendationQueue.pending(recs, now: now).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RecommendationQueueTests`
Expected: FAIL to compile — no `RecommendationQueue`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MustardKit/Logic/RecommendationQueue.swift`:

```swift
import Foundation

/// The triage queue: which recommendations are waiting on you right now. Pure + tested
/// so the "ignore vanishes" + snooze rules live in one place the view just renders.
public enum RecommendationQueue {
    public static func pending(_ recs: [Recommendation], now: Date) -> [Recommendation] {
        recs.filter {
            $0.decision == .pending
                && ($0.snoozedUntil == nil || $0.snoozedUntil! <= now)
                && $0.action != .ignore   // ignored items exist for dedupe/audit but never surface
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RecommendationQueueTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/RecommendationQueue.swift Tests/MustardTests/RecommendationQueueTests.swift
git commit -m "feat(queue): RecommendationQueue.pending hides ignore + future-snoozed recs" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Wire into `AgentService` — normalize at ingest + skip ignore in trust

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift` (`ingest` ~111–119; `applyTrust` line 134)
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the failing test**

Add to `AgentServiceTests` (before its closing `}`):

```swift
    func test_applyTrust_neverAutoExecutesIgnoreRecs() async throws {
        let ctx = try makeContext()
        var called = false
        let stub: ClaudeRun = { _, _ in called = true; return ClaudeResult(ok: true, text: "x") }
        let service = AgentService(context: ctx, claude: stub)
        // Non-gated + high confidence would normally auto-run at Trusted.
        let rec = Recommendation(title: "PO Review", actionType: "ignore",
                                 vaultPath: "/tmp/vault", confidence: 0.95)
        ctx.insert(rec)

        await service.applyTrust(.trusted)

        XCTAssertFalse(called, "ignore recs must never auto-execute")
        XCTAssertEqual(rec.decision, .pending)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentServiceTests/test_applyTrust_neverAutoExecutesIgnoreRecs`
Expected: FAIL — `called` is true / an OutputCard is produced (ignore currently falls through to `execute`).

- [ ] **Step 3: Implement — skip ignore in `applyTrust`**

In `Sources/MustardKit/Agent/AgentService.swift`, change line 134:

```swift
            if rec.action == .fyi { continue }   // awareness items are never auto-actioned
```

to:

```swift
            if rec.action == .fyi || rec.action == .ignore { continue }   // awareness/ignored items are never auto-actioned
```

- [ ] **Step 4: Implement — normalize in `ingest`**

In the same file, replace the `ingest` body (lines ~111–119):

```swift
    private func ingest(_ proposals: [SourceProposal], vaultPath: String) {
        let existing = (try? context.fetch(FetchDescriptor<Recommendation>())) ?? []
        var accepted: [Recommendation] = []
        for p in proposals where SourceDedupe.shouldInsert(p, against: existing + accepted) {
            let rec = Recommendation(from: p, vaultPath: vaultPath)
            context.insert(rec)
            accepted.append(rec)
        }
    }
```

with:

```swift
    private func ingest(_ proposals: [SourceProposal], vaultPath: String) {
        let existing = (try? context.fetch(FetchDescriptor<Recommendation>())) ?? []
        var accepted: [Recommendation] = []
        for raw in proposals {
            // Deterministic Mac-side normalization (logical source + PO-review→ignore)
            // BEFORE dedupe, so dedupe keys on the stable post-normalization source.
            let p = IngestNormalizer.normalize(raw)
            guard SourceDedupe.shouldInsert(p, against: existing + accepted) else { continue }
            let rec = Recommendation(from: p, vaultPath: vaultPath)
            context.insert(rec)
            accepted.append(rec)
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AgentServiceTests`
Expected: PASS (existing + new). The new test confirms ignore is skipped.

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): normalize proposals at ingest; never auto-run ignore recs" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Wire into the view — queue helper + pill colours

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift` (`pending` ~20–24; `ProvenancePill` ~402–414)

No unit test (views are build-verified + eye-checked per CLAUDE.md).

- [ ] **Step 1: Route `pending` through the helper**

In `Sources/MustardKit/Views/AgentConsoleView.swift`, replace:

```swift
    private var pending: [Recommendation] {
        recommendations.filter {
            $0.decision == .pending && ($0.snoozedUntil == nil || $0.snoozedUntil! <= .now)
        }
    }
```

with:

```swift
    private var pending: [Recommendation] {
        RecommendationQueue.pending(recommendations, now: .now)
    }
```

- [ ] **Step 2: Use badge colours in `ProvenancePill`**

In the same file, in `ProvenancePill`'s non-quiet branch, replace:

```swift
                Label(badge.label, systemImage: badge.symbol)
                    .labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#A32D2D"))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(hex: "#FCEBEB"), in: Capsule())
```

with:

```swift
                Label(badge.label, systemImage: badge.symbol)
                    .labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: badge.fgHex))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(hex: badge.bgHex), in: Capsule())
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(console): hide ignore from the queue; per-source pill colours" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Prompt refinement — ticket_write vs create_task

**Files:**
- Modify: `Sources/MustardKit/Agent/VaultSweep.swift` (`prompt`, ~19–28)
- Modify: `docs/scout-routine-prompt.md`
- Test: `Tests/MustardTests/AgentTests.swift` (in `VaultSweepPromptTests`)

- [ ] **Step 1: Write the failing test**

Add to `VaultSweepPromptTests` (alongside the other `test_prompt_*` cases):

```swift
    func test_prompt_distinguishesTicketWriteFromCreateTask() {
        XCTAssertTrue(VaultSweep.prompt.contains("DRAFTING A NEW ticket"))
        XCTAssertTrue(VaultSweep.prompt.contains("EXISTING ticket"))
    }
```

(Both substrings are deliberately contiguous on a single line of the prompt, so they
won't straddle a line-wrap.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VaultSweepPromptTests/test_prompt_distinguishesTicketWriteFromCreateTask`
Expected: FAIL — substrings absent.

- [ ] **Step 3: Add the rule to `VaultSweep.prompt`**

In `Sources/MustardKit/Agent/VaultSweep.swift`, inside the `Rules:` block, immediately
after the "Blocked on others" bullet (the line ending `…you can't act on yet.`) and
keeping the blank line before `Respond with ONLY a JSON array`, add this bullet. Keep
`DRAFTING A NEW ticket` and `EXISTING ticket` each on one line so the test substrings match:

```
    - Ticket vs task: ticket_write means DRAFTING A NEW ticket/story. If an item asks you to
      check, verify, confirm, review, or reply about an EXISTING ticket (e.g. a Jira/Shortcut
      mention carrying a ticket key), use create_task or a draft reply — not ticket_write.
```

- [ ] **Step 4: Add the same rule to the scout prompt**

In `docs/scout-routine-prompt.md`, in the `GROUND + WRITE` section, immediately after the line listing the action tokens (`draft_email, draft_slack, create_task, ticket_write, vault_note, fyi, ignore.`), add:

```
  Ticket vs task: ticket_write = DRAFTING A NEW ticket/story. If the email asks Leon to
  check / verify / confirm / review / reply about an EXISTING ticket, use create_task (a
  to-do) or a draft reply — never ticket_write.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter VaultSweepPromptTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/VaultSweep.swift docs/scout-routine-prompt.md Tests/MustardTests/AgentTests.swift
git commit -m "feat(prompt): separate ticket_write (new ticket) from create_task (act on existing)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: End-to-end ingest test + full suite + build

**Files:**
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the integration test**

Add to `AgentServiceTests`:

```swift
    func test_ingestInbox_reclassifiesGmailJiraNotificationToJiraSource() async throws {
        let ctx = try makeContext()
        let dir = NSTemporaryDirectory() + "mustard-wf-\(UUID().uuidString)"
        let recs = dir + "/_recs"
        try FileManager.default.createDirectory(atPath: recs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let json = #"{"source":"gmail","project":"DL","sourceItemID":"t","sourceEventID":"e1","sourceContext":"Jira · DLA-5280 · mentioned","title":"Confirm DLA-5280 status","body":"b","actionType":"ticket_write","confidence":0.8,"reasoning":"r","draft":"d"}"#
        try json.write(toFile: recs + "/e1.json", atomically: true, encoding: .utf8)
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "[]") })

        await service.ingestInbox(workingDirectory: dir)

        let stored = try ctx.fetch(FetchDescriptor<Recommendation>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.source, "jira", "a Gmail-delivered Jira notification should be stored as source=jira")
    }
```

- [ ] **Step 2: Run it to verify it passes**

Run: `swift test --filter AgentServiceTests/test_ingestInbox_reclassifiesGmailJiraNotificationToJiraSource`
Expected: PASS (the ingest pipeline now normalizes source). If it fails, the wiring in Task 6 is wrong — fix there, not here.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: All tests pass (the prior 73 + the new ones).

- [ ] **Step 4: Build the package**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/MustardTests/AgentTests.swift
git commit -m "test(ingest): end-to-end gmail→jira source reclassification" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Done criteria

- `swift test` and `swift build` both green.
- Leon visually confirms in the running app: Jira recs show a **blue** Jira pill, Shortcut recs a **purple** Shortcut pill (Gmail pill gone for those); PO-review cards and any card re-bucketed to **Ignore** disappear from the Recommendations queue.
- **Leon re-pastes the updated scout prompt** ([docs/scout-routine-prompt.md](../scout-routine-prompt.md)) into his local routine so Feature 3 (ticket vs task) affects future Gmail cards.

## Follow-up to evaluate during execution (from spec)

Audit other surfaces that count "pending" recs — `NotchTicker`, `HoverPanel`, `CommandBarEngine` — and route any "needs you" count through `RecommendationQueue.pending` so ignore items don't inflate it. Fold in only if cheap and consistent; otherwise note as a separate task.
