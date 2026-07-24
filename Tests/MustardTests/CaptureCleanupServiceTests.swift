import XCTest
import SwiftData
@testable import MustardKit

/// `AgentService.cleanupCaptures` — the batched voice-capture cleanup pass
/// (F25 v2/v3, ADR-0011): tier-1 auto-apply, tier-2 recommendation routing,
/// backoff on failure. Claude is stubbed; time and zone are pinned to UTC.
final class CaptureCleanupServiceTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // Wednesday 2026-07-22 10:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_784_714_400)

    @MainActor
    private func ctx() throws -> ModelContext {
        let c = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
            AgentRun.self, AgentMessage.self, CalendarEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    @MainActor
    private func capture(_ transcript: String, in context: ModelContext) -> MustardTask {
        let t = MustardTask(title: VoiceCapture.normalizeTitle(transcript))
        t.source = "voice"
        t.captureState = .raw
        t.captureTranscript = transcript
        context.insert(t)
        return t
    }

    // MARK: - Tier 1: structure + schedule auto-applied

    @MainActor
    func test_tierOne_appliesTitleDescriptionAndSchedule() async throws {
        let context = try ctx()
        let task = capture(
            "create a task for me to release the prep app to testing groups and schedule it on the 9th of August",
            in: context)
        let response = """
        [{"uid": "\(task.uid)", "title": "Release the prep app to testing groups",
          "description": "Push the PREP build out to the testing groups.",
          "scheduled_for": "2026-08-09"}]
        """
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(task.title, "Release the prep app to testing groups")
        XCTAssertEqual(task.notes, "Push the PREP build out to the testing groups.")
        XCTAssertEqual(task.captureState, .cleaned)
        XCTAssertNil(task.captureNextAttemptAt)
        let comps = utc.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(task.scheduledAt))
        XCTAssertEqual([comps.year, comps.month, comps.day, comps.hour], [2026, 8, 9, 9])
        XCTAssertFalse(task.isTimed)
        XCTAssertEqual(task.stage, .planned, "scheduled-placement invariant (BAK-246): date-only → planned")
        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.captureTranscript?.isEmpty, false, "verbatim transcript preserved")
    }

    @MainActor
    func test_tierOne_spokenClockTime_isTimedAndScheduled() async throws {
        let context = try ctx()
        let task = capture("dentist tomorrow at 2:30 pm", in: context)
        let response = """
        [{"uid": "\(task.uid)", "title": "Dentist",
          "scheduled_for": "2026-07-23", "scheduled_time": "14:30"}]
        """
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertTrue(task.isTimed)
        XCTAssertEqual(task.stage, .scheduled, "timed → .scheduled (BAK-246)")
    }

    @MainActor
    func test_tierOne_areaStamped_byName() async throws {
        let context = try ctx()
        let task = capture("release the prep app", in: context)
        let response = """
        [{"uid": "\(task.uid)", "title": "Release the prep app", "area": "Digital Licence"}]
        """
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(task.list?.area?.name, "Digital Licence")
    }

    @MainActor
    func test_tierOne_unknownAreaName_ignored() async throws {
        let context = try ctx()
        let task = capture("do a thing", in: context)
        let response = #"[{"uid": "\#(task.uid)", "title": "Do a thing", "area": "Made Up Client"}]"#
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertNil(task.list, "only known area names may stamp — no invented areas")
        XCTAssertEqual(task.captureState, .cleaned)
    }

    // MARK: - Tier 2: routing is proposed, never applied

    @MainActor
    func test_tierTwo_routeEmitsPendingRecommendation_linkedToTask() async throws {
        let context = try ctx()
        let task = capture(
            "I need you to check the design meeting I had yesterday, and email the action points to Matt",
            in: context)
        let response = """
        [{"uid": "\(task.uid)", "title": "Email Matt the design meeting action points",
          "description": "Pull action points from yesterday's design meeting note.",
          "route": {"action_type": "draft_email", "confidence": 0.85,
                    "reasoning": "the transcript explicitly asks to email Matt",
                    "draft": "Hi Matt, action points from the design meeting: ..."}}]
        """
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        let recs = try context.fetch(FetchDescriptor<Recommendation>())
        XCTAssertEqual(recs.count, 1)
        let rec = recs[0]
        XCTAssertEqual(rec.source, "voice")
        XCTAssertEqual(rec.action, .draftEmail)
        XCTAssertEqual(rec.decision, .pending)
        XCTAssertEqual(rec.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(rec.vaultPath, "/kb")
        XCTAssertTrue(rec.draft.hasPrefix("Hi Matt"))
        XCTAssertTrue(rec.task === task, "approval must promote the SAME captured task")
        XCTAssertTrue(RecommendationQueue.pending([rec], now: now).contains(where: { $0 === rec }),
                      "the route must surface in the triage deck")

        // The capture itself never auto-delegates (ADR-0011 hard line).
        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .inbox)
        XCTAssertEqual(task.captureState, .cleaned)
    }

    @MainActor
    func test_tierTwo_approvedVoiceRec_promotesTheCapturedTask_gatedAndAreaStamped() async throws {
        let context = try ctx()
        let task = capture("email Matt the action points", in: context)
        let response = """
        [{"uid": "\(task.uid)", "title": "Email Matt the action points",
          "area": "Digital Licence",
          "route": {"action_type": "draft_email", "confidence": 0.9,
                    "reasoning": "asks to email", "draft": "Hi Matt,"}}]
        """
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })
        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)
        let rec = try XCTUnwrap(try context.fetch(FetchDescriptor<Recommendation>()).first)

        await svc.decide(rec, .approved)

        XCTAssertEqual(task.owner, .agent, "approval — and only approval — hands the task off")
        XCTAssertEqual(task.stage, .queued, "outward action stages for the connected worker")
        XCTAssertTrue(task.isGated, "draft_email stays always-gated on the board card")
        XCTAssertEqual(task.list?.area?.name, "Digital Licence",
                       "tier-1 area stamp is what routes the bridge export (BAK-90)")
        let all = try context.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(all.count, 1, "no duplicate task may be created on approval")
    }

    // MARK: - Failure paths

    @MainActor
    func test_claudeFailure_backsOffEveryDueCapture() async throws {
        let context = try ctx()
        let task = capture("buy milk", in: context)
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: false, text: "boom") })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(task.captureState, .raw)
        XCTAssertEqual(task.captureAttempts, 1)
        XCTAssertEqual(task.captureNextAttemptAt, now.addingTimeInterval(60))
        XCTAssertNotNil(svc.lastError)
    }

    @MainActor
    func test_unparseableOutput_backsOff() async throws {
        let context = try ctx()
        let task = capture("buy milk", in: context)
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: "sure, done!") })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(task.captureAttempts, 1)
        XCTAssertNotNil(svc.lastError)
    }

    @MainActor
    func test_captureMissingFromResults_backsOff_othersApply() async throws {
        let context = try ctx()
        let done = capture("buy milk", in: context)
        let skipped = capture("mumble mumble", in: context)
        let response = #"[{"uid": "\#(done.uid)", "title": "Buy milk"}]"#
        let svc = AgentService(context: context, claude: { _, _ in .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(done.captureState, .cleaned)
        XCTAssertEqual(skipped.captureState, .raw)
        XCTAssertEqual(skipped.captureAttempts, 1)
    }

    // MARK: - Gate + queue discipline

    @MainActor
    func test_noDueCaptures_makesNoClaudeCall() async throws {
        let context = try ctx()
        let done = capture("done already", in: context)
        done.captureState = .cleaned
        var calls = 0
        let svc = AgentService(context: context, claude: { _, _ in calls += 1; return .init(ok: true, text: "[]") })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func test_gateBusy_consumesNoAttempt() async throws {
        let context = try ctx()
        let gate = AgentExecutionGate()
        let held = gate.tryAcquire(owner: "test")   // simulate a running delegated task
        defer { if let held { gate.release(held) } }
        var calls = 0
        let task = capture("buy milk", in: context)
        let svc = AgentService(
            context: context,
            claude: { _, _ in calls += 1; return .init(ok: true, text: "[]") },
            executionGate: gate)

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(task.captureAttempts, 0, "a busy slot is not a failure — no ladder step")
        XCTAssertEqual(task.captureState, .raw)
    }

    @MainActor
    func test_cleanedCaptures_neverReprocessed() async throws {
        let context = try ctx()
        let task = capture("buy milk", in: context)
        var calls = 0
        let response = #"[{"uid": "\#(task.uid)", "title": "Buy milk"}]"#
        let svc = AgentService(context: context, claude: { _, _ in calls += 1; return .init(ok: true, text: response) })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)
        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func test_promptedTranscript_isTheVerbatimCapture() async throws {
        let context = try ctx()
        let task = capture("email Matt the action points.", in: context)
        var seenPrompt = ""
        let svc = AgentService(context: context, claude: { prompt, _ in
            seenPrompt = prompt
            return .init(ok: true, text: #"[{"uid": "\#(task.uid)", "title": "Email Matt"}]"#)
        })

        await svc.cleanupCaptures(workingDirectory: "/kb", now: now, calendar: utc)

        XCTAssertTrue(seenPrompt.contains("email Matt the action points."),
                      "cleanup reads the raw transcript, not the normalized title")
        XCTAssertTrue(seenPrompt.contains(task.uid))
    }
}
