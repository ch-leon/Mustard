import XCTest
import SwiftData
@testable import MustardKit

final class VaultSweepParserTests: XCTestCase {
    func test_parse_happyPath() {
        let text = #"[{"title": "Revive SDK note", "body": "Stale since May.", "action_type": "vault_note"}]"#
        let result = VaultSweep.parse(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Revive SDK note")
        XCTAssertEqual(result[0].body, "Stale since May.")
    }

    func test_parse_codeFencedAndProseWrapped() {
        let text = """
        Here are my recommendations:
        ```json
        [{"title": "A"}, {"title": "B", "body": "b"}]
        ```
        Hope that helps!
        """
        let result = VaultSweep.parse(text)
        XCTAssertEqual(result.map(\.title), ["A", "B"])
        XCTAssertEqual(result[1].body, "b")
    }

    func test_parse_garbageReturnsEmpty() {
        XCTAssertEqual(VaultSweep.parse("I could not find anything."), [])
        XCTAssertEqual(VaultSweep.parse(""), [])
        XCTAssertEqual(VaultSweep.parse("[not json"), [])
    }

    func test_parse_capsAtFive() {
        let items = (1...8).map { #"{"title": "t\#($0)"}"# }.joined(separator: ",")
        XCTAssertEqual(VaultSweep.parse("[\(items)]").count, 5)
    }

    func test_parse_readsConfidenceReasoningDraft() {
        let text = #"[{"title":"Reply","action_type":"draft_email","confidence":0.82,"reasoning":"asked by EOD","draft":"Hi Kamil,"}]"#
        let p = VaultSweep.parse(text)[0]
        XCTAssertEqual(p.actionType, "draft_email")
        XCTAssertEqual(p.confidence, 0.82, accuracy: 0.001)
        XCTAssertEqual(p.reasoning, "asked by EOD")
        XCTAssertEqual(p.draft, "Hi Kamil,")
    }

    func test_parse_defaultsAndClampsConfidence() {
        let missing = VaultSweep.parse(#"[{"title":"x"}]"#)[0]
        XCTAssertEqual(missing.confidence, 0.5, accuracy: 0.001)
        XCTAssertEqual(missing.reasoning, "")
        let over = VaultSweep.parse(#"[{"title":"x","confidence":1.8}]"#)[0]
        XCTAssertEqual(over.confidence, 1.0, accuracy: 0.001)
    }
}

@MainActor
final class AgentServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, CalendarEvent.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func test_sweep_insertsPendingRecommendations() async throws {
        let ctx = try makeContext()
        let stub: ClaudeRun = { _, _ in
            ClaudeResult(ok: true, text: #"[{"title": "One"}, {"title": "Two"}]"#)
        }
        let service = AgentService(context: ctx, claude: stub)
        await service.sweep(vaultPath: "/tmp/vault")

        let recs = try ctx.fetch(FetchDescriptor<Recommendation>())
        XCTAssertEqual(recs.count, 2)
        XCTAssertTrue(recs.allSatisfy { $0.decision == .pending })
        XCTAssertNil(service.lastError)
    }

    func test_sweep_failureSetsError_insertsNothing() async throws {
        let ctx = try makeContext()
        let stub: ClaudeRun = { _, _ in ClaudeResult(ok: false, text: "401") }
        let service = AgentService(context: ctx, claude: stub)
        await service.sweep(vaultPath: "/tmp/vault")

        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Recommendation>()).count, 0)
    }

    func test_approve_executesAndProducesExactlyOneCard() async throws {
        let ctx = try makeContext()
        let stub: ClaudeRun = { prompt, _ in
            ClaudeResult(ok: true, text: prompt.contains("Execute") ? "Did the thing." : "[]")
        }
        let service = AgentService(context: ctx, claude: stub)
        let rec = Recommendation(title: "Do it", vaultPath: "/tmp/vault")
        ctx.insert(rec)

        await service.decide(rec, .approved)

        XCTAssertEqual(rec.decision, .approved)
        XCTAssertEqual(rec.executionState, .finished)
        let cards = try ctx.fetch(FetchDescriptor<OutputCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.content, "Did the thing.")
        XCTAssertEqual(cards.first?.review, .pending)
    }

    func test_execute_failureStillProducesCard_markedFailed() async throws {
        let ctx = try makeContext()
        let stub: ClaudeRun = { _, _ in ClaudeResult(ok: false, text: "boom") }
        let service = AgentService(context: ctx, claude: stub)
        let rec = Recommendation(title: "Do it", vaultPath: "/tmp/vault")
        ctx.insert(rec)

        await service.execute(rec)

        XCTAssertEqual(rec.executionState, .failed)
        let cards = try ctx.fetch(FetchDescriptor<OutputCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.kind, "error")
    }

    func test_deny_doesNotExecute() async throws {
        let ctx = try makeContext()
        var called = false
        let stub: ClaudeRun = { _, _ in called = true; return ClaudeResult(ok: true, text: "") }
        let service = AgentService(context: ctx, claude: stub)
        let rec = Recommendation(title: "Nope", vaultPath: "/tmp/vault")
        ctx.insert(rec)

        await service.decide(rec, .denied)

        XCTAssertEqual(rec.decision, .denied)
        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }

    func test_applyTrust_supervised_autoRunsNonGated_outputAwaitsReview() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "done") })
        let rec = Recommendation(title: "Note", actionType: "vault_note", vaultPath: "/v", confidence: 0.9)
        ctx.insert(rec)

        await service.applyTrust(.supervised)

        XCTAssertEqual(rec.decision, .approved)
        XCTAssertEqual(rec.executionState, .finished)
        let cards = try ctx.fetch(FetchDescriptor<OutputCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.review, .pending)
    }

    func test_applyTrust_trusted_autoAcceptsNonGated() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "done") })
        let rec = Recommendation(title: "Note", actionType: "vault_note", vaultPath: "/v", confidence: 0.9)
        ctx.insert(rec)

        await service.applyTrust(.trusted)

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).first?.review, .accepted)
    }

    func test_applyTrust_skipsLowConfidence_evenTrusted() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Shaky", actionType: "vault_note", vaultPath: "/v", confidence: 0.3)
        ctx.insert(rec)

        await service.applyTrust(.trusted)

        XCTAssertEqual(rec.decision, .pending)
        XCTAssertFalse(called)
    }

    func test_commentAndSnooze() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "x", vaultPath: "/v")
        ctx.insert(rec)
        service.comment(rec, "make it shorter")
        let until = Date.now.addingTimeInterval(3600)
        service.snooze(rec, until: until)
        XCTAssertEqual(rec.comment, "make it shorter")
        XCTAssertEqual(rec.snoozedUntil, until)
        XCTAssertEqual(rec.decision, .pending)
    }

    func test_applyTrust_neverTouchesGatedActions() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in called = true; return ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Email Kamil", actionType: "draft_email", vaultPath: "/v")
        ctx.insert(rec)

        await service.applyTrust(.autonomous)

        XCTAssertEqual(rec.decision, .pending)
        XCTAssertFalse(called)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }
}
