import Foundation
import CryptoKit

/// One harvested action item from a meeting note's "Code Heroes tasks" section.
public struct ParsedMeetingTask: Equatable {
    public let title: String
    public let isDone: Bool
    public let due: Date?
    /// The original line verbatim — kept so the sync can re-locate it for write-back.
    public let rawLine: String
    public let notePath: String
    /// Stable identity for dedup + line-locating (see `originKey`).
    public let originKey: String
}

/// Pure, deterministic harvester for the curated `- [ ]` checklist that Leon's
/// Sync pipeline writes into each meeting note. No model call — the extraction
/// and owner-filtering already happened upstream; Mustard only lifts the lines.
public enum MeetingTaskParser {
    /// Heading whose checklist we harvest — case-insensitive, trailing text tolerated
    /// (`### Code Heroes tasks (Leon)` matches).
    static let sectionHeading = "code heroes tasks"

    private static let checkboxPrefix = #"^\s*[-*]\s+\[[ xX]\]\s*"#
    private static let donePattern = #"✅\s*\d{4}-\d{2}-\d{2}"#
    private static let duePattern = #"📅\s*\d{4}-\d{2}-\d{2}"#
    private static let blockIdSuffix = #"\s*\^[\w-]+\s*$"#
    private static let isoDate = #"\d{4}-\d{2}-\d{2}"#
    /// Obsidian Tasks metadata emoji we drop from the human-readable title.
    private static let metaEmoji = CharacterSet(charactersIn: "⏫🔺🔼🔽⏬🔁⏳🛫➕❌")

    /// Harvest the `- [ ]` lines under the "Code Heroes tasks" heading, in order.
    public static func parse(_ text: String, notePath: String) -> [ParsedMeetingTask] {
        var out: [ParsedMeetingTask] = []
        var inSection = false
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop { $0 == "#" }
                    .trimmingCharacters(in: .whitespaces).lowercased()
                inSection = heading.hasPrefix(sectionHeading)
                continue
            }
            guard inSection, isCheckbox(trimmed) else { continue }
            out.append(
                ParsedMeetingTask(
                    title: extractTitle(rawLine),
                    isDone: isChecked(rawLine),
                    due: dueDate(rawLine),
                    rawLine: rawLine,
                    notePath: notePath,
                    originKey: originKey(notePath: notePath, line: rawLine)
                )
            )
        }
        return out
    }

    static func isCheckbox(_ line: String) -> Bool {
        line.range(of: checkboxPrefix, options: .regularExpression) != nil
    }

    static func isChecked(_ line: String) -> Bool {
        guard let r = line.range(of: #"\[[ xX]\]"#, options: .regularExpression) else { return false }
        return line[r].lowercased().contains("x")
    }

    static func dueDate(_ line: String) -> Date? {
        guard let r = line.range(of: duePattern, options: .regularExpression),
              let dr = line[r].range(of: isoDate, options: .regularExpression) else { return nil }
        return dateFormatter.date(from: String(line[r][dr]))
    }

    /// Human-readable title: line minus checkbox, dates, priority emoji, block id.
    static func extractTitle(_ line: String) -> String {
        var s = line.replacingOccurrences(of: checkboxPrefix, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: donePattern, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: duePattern, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: blockIdSuffix, with: "", options: .regularExpression)
        var kept = String.UnicodeScalarView()
        for scalar in s.unicodeScalars where !metaEmoji.contains(scalar) { kept.append(scalar) }
        return collapseWhitespace(String(kept))
    }

    /// Stable identity: SHA-256 of `notePath` + the line with its checkbox state
    /// and `✅ <date>` stripped — so `- [ ]` → `- [x] ✅ date` keeps the same key.
    public static func originKey(notePath: String, line: String) -> String {
        sha256Hex(notePath + "\n" + normalize(line))
    }

    static func normalize(_ line: String) -> String {
        var s = line.replacingOccurrences(of: checkboxPrefix, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: donePattern, with: "", options: .regularExpression)
        return collapseWhitespace(s)
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
