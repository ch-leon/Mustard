import XCTest
@testable import MustardKit

/// Prompt, parser, and schedule resolution for the voice cleanup pass (F25 v2/v3).
/// Time/zone pinned to UTC per the testing rules — never the ambient clock.
final class CaptureCleanupTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()
    // Wednesday 2026-07-22 10:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_784_714_400)

    private func items(_ pairs: [(String, String)]) -> [CaptureCleanup.Item] {
        pairs.map { CaptureCleanup.Item(uid: $0.0, transcript: $0.1) }
    }

    // MARK: - Prompt

    func test_prompt_carriesTodayAndTimezone() {
        let p = CaptureCleanup.prompt(
            items: items([("u1", "buy milk")]), now: now, calendar: utc,
            areaNames: ["Digital Licence", "Code Heroes"])
        XCTAssertTrue(p.contains("2026-07-22"), "model needs today to resolve relative dates")
        XCTAssertTrue(p.contains("Wednesday"))
        XCTAssertTrue(p.contains("GMT") || p.contains("UTC"))
    }

    func test_prompt_listsEveryUIDAndTranscript() {
        let p = CaptureCleanup.prompt(
            items: items([("u1", "buy milk"), ("u2", "email Matt")]),
            now: now, calendar: utc, areaNames: [])
        XCTAssertTrue(p.contains("u1") && p.contains("buy milk"))
        XCTAssertTrue(p.contains("u2") && p.contains("email Matt"))
    }

    func test_prompt_offersAreasAndConstrainsRouteActions() {
        let p = CaptureCleanup.prompt(
            items: items([("u1", "x")]), now: now, calendar: utc,
            areaNames: ["Digital Licence"])
        XCTAssertTrue(p.contains("Digital Licence"))
        for allowed in ["draft_email", "draft_slack", "ticket_write", "vault_note"] {
            XCTAssertTrue(p.contains(allowed), "route menu must offer \(allowed)")
        }
        XCTAssertTrue(p.contains("Do not read or modify any files"),
                      "cleanup is a text transform, not a vault pass")
    }

    // MARK: - Parser

    func test_parse_tierOneHappyPath() {
        let text = """
        [{"uid": "u1", "title": "Release the prep app to testing groups",
          "description": "Push the PREP build out to the testing groups.",
          "scheduled_for": "2026-08-09"}]
        """
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertEqual(rs.count, 1)
        XCTAssertEqual(rs[0].uid, "u1")
        XCTAssertEqual(rs[0].title, "Release the prep app to testing groups")
        XCTAssertEqual(rs[0].scheduledFor, "2026-08-09")
        XCTAssertNil(rs[0].scheduledTime)
        XCTAssertNil(rs[0].route)
    }

    func test_parse_routeHappyPath() {
        let text = """
        [{"uid": "u2", "title": "Email Matt the design meeting action points",
          "description": "Review yesterday's design meeting notes.",
          "route": {"action_type": "draft_email", "confidence": 0.85,
                    "reasoning": "explicitly asks to email Matt",
                    "draft": "Hi Matt, here are the action points..."}}]
        """
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u2"]),
              let route = rs.first?.route else {
            return XCTFail("expected a routed result")
        }
        XCTAssertEqual(route.actionType, "draft_email")
        XCTAssertEqual(route.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(route.reasoning, "explicitly asks to email Matt")
        XCTAssertTrue(route.draft.hasPrefix("Hi Matt"))
    }

    func test_parse_codeFencedAndProseWrapped() {
        let text = """
        Here you go:
        ```json
        [{"uid": "u1", "title": "Buy milk"}]
        ```
        """
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertEqual(rs.map(\.title), ["Buy milk"])
    }

    func test_parse_unknownUID_dropped() {
        let text = #"[{"uid": "evil", "title": "x"}, {"uid": "u1", "title": "ok"}]"#
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertEqual(rs.map(\.uid), ["u1"])
    }

    func test_parse_missingOrEmptyTitle_dropped() {
        let text = #"[{"uid": "u1"}, {"uid": "u2", "title": ""}]"#
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1", "u2"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertTrue(rs.isEmpty)
    }

    func test_parse_disallowedRouteAction_dropsRouteKeepsTierOne() {
        // create_task routing is meaningless (it IS a task) and anything unknown is unsafe.
        let text = """
        [{"uid": "u1", "title": "Buy milk",
          "route": {"action_type": "create_task", "confidence": 0.9}},
         {"uid": "u2", "title": "Do thing",
          "route": {"action_type": "rm_rf", "confidence": 0.9}}]
        """
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1", "u2"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertEqual(rs.count, 2)
        XCTAssertTrue(rs.allSatisfy { $0.route == nil })
    }

    func test_parse_routeConfidenceClampedAndDefaulted() {
        let text = """
        [{"uid": "u1", "title": "A", "route": {"action_type": "draft_email", "confidence": 1.7}},
         {"uid": "u2", "title": "B", "route": {"action_type": "vault_note"}}]
        """
        guard case .results(let rs) = CaptureCleanup.parseOutcome(text, validUIDs: ["u1", "u2"]) else {
            return XCTFail("expected .results")
        }
        XCTAssertEqual(rs[0].route?.confidence, 1.0)
        XCTAssertEqual(rs[1].route?.confidence ?? -1, 0.5, accuracy: 0.001)
    }

    func test_parse_garbage_isUnparseable() {
        XCTAssertEqual(CaptureCleanup.parseOutcome("no json here", validUIDs: ["u1"]), .unparseable)
        XCTAssertEqual(CaptureCleanup.parseOutcome("", validUIDs: ["u1"]), .unparseable)
        XCTAssertEqual(CaptureCleanup.parseOutcome("[truncated", validUIDs: ["u1"]), .unparseable)
    }

    func test_parse_emptyArray_isResultsNotUnparseable() {
        XCTAssertEqual(CaptureCleanup.parseOutcome("[]", validUIDs: ["u1"]), .results([]))
    }

    // MARK: - resolveSchedule

    func test_resolve_dateOnly_landsNineAM_untimed() {
        let r = CaptureCleanup.resolveSchedule(date: "2026-08-09", time: nil, calendar: utc)
        XCTAssertNotNil(r)
        let comps = utc.dateComponents([.year, .month, .day, .hour, .minute], from: r!.at)
        XCTAssertEqual([comps.year, comps.month, comps.day, comps.hour, comps.minute],
                       [2026, 8, 9, 9, 0])
        XCTAssertFalse(r!.timed)
    }

    func test_resolve_dateAndTime_isTimed() {
        let r = CaptureCleanup.resolveSchedule(date: "2026-08-09", time: "14:30", calendar: utc)
        let comps = utc.dateComponents([.hour, .minute], from: r!.at)
        XCTAssertEqual([comps.hour, comps.minute], [14, 30])
        XCTAssertTrue(r!.timed)
    }

    func test_resolve_nilOrMalformed_returnsNil() {
        XCTAssertNil(CaptureCleanup.resolveSchedule(date: nil, time: "14:30", calendar: utc))
        XCTAssertNil(CaptureCleanup.resolveSchedule(date: "9th of August", time: nil, calendar: utc))
        XCTAssertNil(CaptureCleanup.resolveSchedule(date: "2026-13-40", time: nil, calendar: utc))
        XCTAssertNil(CaptureCleanup.resolveSchedule(date: "2026-08-09", time: "25:99", calendar: utc))
    }

    func test_resolve_nonNumericTime_rejectsPair() {
        // A provided-but-invalid time rejects the whole pair rather than guessing a
        // clock time; the capture just stays unscheduled (still editable by hand).
        XCTAssertNil(CaptureCleanup.resolveSchedule(date: "2026-08-09", time: "morning", calendar: utc))
    }
}
