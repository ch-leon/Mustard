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

final class VaultSweepPromptTests: XCTestCase {
    func test_prompt_ignoresAppInternalFolders() {
        XCTAssertTrue(VaultSweep.prompt.contains("_filed/"))
        XCTAssertTrue(VaultSweep.prompt.contains("_recs/"))
    }

    func test_executePrompt_includesDraftAsStartingPoint() {
        let p = VaultSweep.executePrompt(
            title: "Reply to Kamil", body: "He asked for the figures.",
            action: .draftEmail, draft: "Hi Kamil, here are the Q2 figures…"
        )
        XCTAssertTrue(p.contains("Hi Kamil, here are the Q2 figures…"))
        XCTAssertTrue(p.contains("Starting point"))
    }

    func test_executePrompt_emailPhrasingDiffersFromVaultNote() {
        let email = VaultSweep.executePrompt(title: "t", body: "b", action: .draftEmail)
        let note = VaultSweep.executePrompt(title: "t", body: "b", action: .vaultNote)
        XCTAssertTrue(email.lowercased().contains("email"))
        XCTAssertTrue(note.lowercased().contains("knowledge base"))
        XCTAssertNotEqual(email, note)
    }

    func test_executePrompt_gatedActionStaysDraftOnly() {
        let p = VaultSweep.executePrompt(title: "t", body: "b", action: .draftEmail)
        XCTAssertTrue(p.lowercased().contains("do not send"))
    }

    func test_executePrompt_withFeedbackAndPriorOutput_instructsRevision() {
        let p = VaultSweep.executePrompt(
            title: "t", body: "b", action: .vaultNote,
            feedback: "make it shorter", priorOutput: "A long previous draft."
        )
        XCTAssertTrue(p.contains("make it shorter"))
        XCTAssertTrue(p.contains("A long previous draft."))
        XCTAssertTrue(p.lowercased().contains("revis"))
    }

    func test_executePrompt_withoutFeedbackOrPrior_omitsRevisionBlock() {
        let p = VaultSweep.executePrompt(title: "t", body: "b", action: .vaultNote)
        XCTAssertFalse(p.contains("You previously produced"))
        XCTAssertFalse(p.contains("This is a revision."))
    }

    func test_executePrompt_emptyDraftFallsBackToBody() {
        let p = VaultSweep.executePrompt(
            title: "t", body: "The body text.", action: .vaultNote, draft: ""
        )
        XCTAssertTrue(p.contains("The body text."))
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
            // Key on the rec title rather than prompt copy, so the test is robust
            // to prompt wording changes.
            ClaudeResult(ok: true, text: prompt.contains("Do it") ? "Did the thing." : "[]")
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

    func test_execute_buildsGroundedPrompt_includingDraft() async throws {
        let ctx = try makeContext()
        var captured = ""
        let service = AgentService(context: ctx, claude: { prompt, _ in
            captured = prompt; return ClaudeResult(ok: true, text: "ok")
        })
        let rec = Recommendation(
            title: "Reply", actionType: "draft_email", vaultPath: "/v",
            draft: "Hi Kamil,"
        )
        ctx.insert(rec)

        await service.execute(rec)

        XCTAssertTrue(captured.contains("Hi Kamil,"))
        XCTAssertTrue(captured.lowercased().contains("email"))
    }

    func test_decide_approved_passesTriageCommentAsFeedback() async throws {
        let ctx = try makeContext()
        var captured = ""
        let service = AgentService(context: ctx, claude: { prompt, _ in
            captured = prompt; return ClaudeResult(ok: true, text: "ok")
        })
        let rec = Recommendation(title: "Note", actionType: "vault_note", vaultPath: "/v")
        ctx.insert(rec)
        service.comment(rec, "keep it under 100 words")

        await service.decide(rec, .approved)

        XCTAssertTrue(captured.contains("keep it under 100 words"))
    }

    func test_revise_retiresOldCard_createsNewPending_chainsHistory() async throws {
        let ctx = try makeContext()
        var captured = ""
        let service = AgentService(context: ctx, claude: { prompt, _ in
            captured = prompt; return ClaudeResult(ok: true, text: "v2 output")
        })
        let rec = Recommendation(title: "Note", actionType: "vault_note", vaultPath: "/v")
        ctx.insert(rec)
        let first = OutputCard(content: "v1 output", recommendation: rec)
        ctx.insert(first)

        let newCard = await service.revise(first, feedback: "make it shorter")

        XCTAssertEqual(first.review, .revised)
        XCTAssertNotNil(newCard)
        XCTAssertEqual(newCard?.review, .pending)
        XCTAssertEqual(newCard?.content, "v2 output")
        XCTAssertEqual(rec.comment, "make it shorter")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 2)
        XCTAssertTrue(captured.contains("v1 output"))
        XCTAssertTrue(captured.contains("make it shorter"))
    }

    func test_revise_emptyFeedback_stillRevisesWithPriorOutput() async throws {
        let ctx = try makeContext()
        var captured = ""
        let service = AgentService(context: ctx, claude: { prompt, _ in
            captured = prompt; return ClaudeResult(ok: true, text: "v2")
        })
        let rec = Recommendation(title: "Note", actionType: "vault_note", vaultPath: "/v")
        ctx.insert(rec)
        let first = OutputCard(content: "v1 output", recommendation: rec)
        ctx.insert(first)

        let newCard = await service.revise(first, feedback: "")

        XCTAssertNotNil(newCard)
        XCTAssertTrue(captured.contains("v1 output"))
    }

    func test_revise_noRecommendation_isNoOp() async throws {
        let ctx = try makeContext()
        var called = false
        let service = AgentService(context: ctx, claude: { _, _ in
            called = true; return ClaudeResult(ok: true, text: "x")
        })
        let orphan = OutputCard(content: "orphan", recommendation: nil)
        ctx.insert(orphan)

        let result = await service.revise(orphan, feedback: "change it")

        XCTAssertNil(result)
        XCTAssertFalse(called)
        XCTAssertEqual(orphan.review, .pending)
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
}
