import Foundation

/// Pure formatting + pathing for the curated-KB rolling log (the "Keep" target).
/// The actual append is a thin side effect in `AgentService`; content and path live
/// here so they stay unit-tested (CLAUDE.md: logic is TDD; pin time/timezone).
public enum InboxLog {
    /// UTC is always a valid `TimeZone` identifier, so this is non-nil in practice;
    /// hoisted to a constant purely for style consistency with the rest of Logic/.
    /// (Must be `public`: a `public` function's default-argument value must be able
    /// to see it.)
    public static let utc = TimeZone(identifier: "UTC")!

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
        timeZone: TimeZone = utc
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
