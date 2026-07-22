import Foundation

/// Prompt + parser for the voice-capture cleanup pass (F25 v2/v3, ADR-0011): one
/// batched `claude -p` text transform that structures raw spoken transcripts into
/// title/description/schedule/area (tier 1 — auto-applied by `AgentService`) and,
/// when a capture is agent-shaped, a proposed route into the recommendation loop
/// (tier 2 — never auto-applied). Pure, like `VaultSweep`.
public enum CaptureCleanup {
    public struct Item: Equatable {
        public let uid: String
        public let transcript: String

        public init(uid: String, transcript: String) {
            self.uid = uid
            self.transcript = transcript
        }
    }

    /// Route action types the parser accepts. `create_task` is deliberately absent —
    /// "it's just a task" is tier 1, not a route — and anything unknown is unsafe.
    public static let allowedRouteActions: Set<String> = [
        RecommendationAction.draftEmail.rawValue,
        RecommendationAction.draftSlack.rawValue,
        RecommendationAction.ticket.rawValue,
        RecommendationAction.vaultNote.rawValue,
    ]

    public struct Route: Equatable {
        public let actionType: String
        public let confidence: Double
        public let reasoning: String
        public let draft: String
    }

    public struct Result: Equatable {
        public let uid: String
        public let title: String
        public let description: String
        /// "YYYY-MM-DD" as returned by the model; resolved via `resolveSchedule`.
        public let scheduledFor: String?
        /// "HH:mm" (24h) — presence makes the schedule time-anchored (`isTimed`).
        public let scheduledTime: String?
        /// One of the area names offered in the prompt, or nil.
        public let area: String?
        public let route: Route?
    }

    /// Same contract as `VaultSweep.ParseOutcome`: distinguish "ran and returned
    /// nothing" from "output wasn't the expected shape at all".
    public enum ParseOutcome: Equatable {
        case results([Result])
        case unparseable
    }

    /// Build the batched cleanup prompt. `now`/`calendar` pin "today" so relative
    /// spoken dates ("yesterday", "the 9th of August") resolve deterministically.
    public static func prompt(
        items: [Item], now: Date, calendar: Calendar, areaNames: [String]
    ) -> String {
        let dateText = dayStamp(now: now, calendar: calendar)
        let zone = calendar.timeZone.identifier
        let areaLine = areaNames.isEmpty
            ? "There are no known areas — always omit \"area\"."
            : "Known areas (use EXACTLY one of these strings, or omit): " +
              areaNames.map { "\"\($0)\"" }.joined(separator: ", ") + "."
        let itemLines = items
            .map { #"{"uid": "\#($0.uid)", "transcript": "\#(escape($0.transcript))"}"# }
            .joined(separator: "\n")

        return """
        You are cleaning up voice-captured to-do items. Each input below is a raw
        speech-to-text transcript of the user speaking a task out loud. Today is
        \(dateText) (timezone \(zone)).

        Do not read or modify any files. This is a pure text transformation — respond
        from the transcripts alone.

        For each input item, produce one output object:
        - uid: copy the input uid EXACTLY.
        - title: a short imperative task title (under ~70 characters), with
          speech-to-text artifacts fixed. Never leave it empty.
        - description: the remaining detail as 1-3 plain sentences ("" if none).
        - scheduled_for: "YYYY-MM-DD" ONLY when the transcript names a date or a
          clearly resolvable relative day ("tomorrow", "the 9th of August"). Resolve
          relative dates against today, choosing the next FUTURE occurrence. Omit
          when unsure — never guess.
        - scheduled_time: "HH:mm" 24-hour, ONLY when a clock time was spoken.
        - area: which area this belongs to, ONLY when the transcript makes it
          obvious. \(areaLine)
        - route: include ONLY when the transcript asks for work an AI agent should
          do on the user's behalf (checking notes, drafting an email/Slack message,
          writing a ticket) rather than a plain reminder. When included:
          {"action_type": one of "draft_email", "draft_slack", "ticket_write",
           "vault_note"; "confidence": 0.0-1.0 that this should go to the agent;
          "reasoning": one sentence; "draft": the proposed deliverable text}.
          A plain to-do the user will handle personally gets NO route. Routing is a
          PROPOSAL the user reviews — when in doubt, omit it.

        Input items:
        \(itemLines)

        Respond with ONLY a JSON array, no prose, one object per input item:
        [{"uid": "...", "title": "...", "description": "...",
          "scheduled_for": "2026-08-09", "scheduled_time": "14:30",
          "area": "Digital Licence",
          "route": {"action_type": "draft_email", "confidence": 0.8,
                    "reasoning": "...", "draft": "..."}}]
        Omit any optional field that does not apply (or use null).
        """
    }

    /// Extract results from model output (code-fence tolerant, like `VaultSweep`).
    /// Objects with unknown uids or empty titles are dropped — a dropped capture
    /// simply stays raw and retries on the backoff ladder.
    public static func parseOutcome(_ text: String, validUIDs: Set<String>) -> ParseOutcome {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"), start < end else { return .unparseable }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .unparseable
        }
        let results = raw.compactMap { item -> Result? in
            guard let uid = item["uid"] as? String, validUIDs.contains(uid),
                  let title = item["title"] as? String, !title.isEmpty else { return nil }
            return Result(
                uid: uid,
                title: title,
                description: item["description"] as? String ?? "",
                scheduledFor: item["scheduled_for"] as? String,
                scheduledTime: item["scheduled_time"] as? String,
                area: item["area"] as? String,
                route: parseRoute(item["route"])
            )
        }
        return .results(results)
    }

    private static func parseRoute(_ raw: Any?) -> Route? {
        guard let dict = raw as? [String: Any],
              let actionType = dict["action_type"] as? String,
              allowedRouteActions.contains(actionType) else { return nil }
        let confidence = (dict["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        return Route(
            actionType: actionType,
            confidence: min(max(confidence, 0), 1),
            reasoning: dict["reasoning"] as? String ?? "",
            draft: dict["draft"] as? String ?? ""
        )
    }

    /// Resolve the model's ("YYYY-MM-DD", "HH:mm"?) pair into a concrete date via
    /// the injected calendar. Date-only lands at 9:00 untimed (the quick-capture
    /// convention); a spoken clock time makes it timed. Any malformed component
    /// rejects the pair — the capture stays unscheduled rather than guessing.
    public static func resolveSchedule(
        date: String?, time: String?, calendar: Calendar
    ) -> (at: Date, timed: Bool)? {
        guard let date, let (year, month, day) = split(date, separator: "-", counts: (4, 2, 2)),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var hour = 9, minute = 0, timed = false
        if let time {
            guard let (h, m, _) = splitTime(time),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            hour = h; minute = m; timed = true
        }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        guard let at = calendar.date(from: comps),
              // Reject overflow rollovers (e.g. Feb 31 → Mar 3): the round-trip must agree.
              calendar.component(.day, from: at) == day,
              calendar.component(.month, from: at) == month else { return nil }
        return (at, timed)
    }

    // MARK: - Helpers

    private static func dayStamp(now: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let y = comps.year, let m = comps.month, let d = comps.day,
              let weekday = comps.weekday else { return "" }
        let name = calendar.weekdaySymbols[weekday - 1]
        return String(format: "%@ %04d-%02d-%02d", name, y, m, d)
    }

    /// Minimal JSON string escaping for transcripts embedded in the prompt.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func split(
        _ s: String, separator: Character, counts: (Int, Int, Int)
    ) -> (Int, Int, Int)? {
        let parts = s.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == counts.0, parts[1].count == counts.1, parts[2].count == counts.2,
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        return (a, b, c)
    }

    private static func splitTime(_ s: String) -> (Int, Int, Int)? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m, 0)
    }
}
