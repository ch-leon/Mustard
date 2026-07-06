import Foundation

/// Pure header metadata for the Craft note header (Phase 2a): word count over the
/// frontmatter-stripped body, and the quiet "project · edited · words" line.
public enum NoteMetadata {

    /// Words = whitespace-separated tokens containing at least one letter or digit,
    /// counted over the frontmatter-stripped body — so "# Two words" counts 2 and
    /// bare syntax tokens ("#", "-", "---", "```") never inflate the count.
    public static func wordCount(_ source: String) -> Int {
        Frontmatter.parse(source).body
            .split(whereSeparator: \.isWhitespace)
            .filter { token in token.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    /// "Mustard · edited today · 214 words" — nil `modified` drops the middle
    /// segment. `now`/`calendar` are injected (CLAUDE.md: date logic never reads
    /// the ambient clock); the view passes `.now` / `.current`.
    public static func line(project: String, modified: Date?, wordCount: Int,
                            now: Date, calendar: Calendar) -> String {
        var segments = [project]
        if let modified {
            segments.append("edited \(editedPhrase(modified, now: now, calendar: calendar))")
        }
        segments.append(wordCount == 1 ? "1 word" : "\(wordCount) words")
        return segments.joined(separator: " · ")
    }

    /// today / yesterday / "26 Jun" — the dated form via a fixed `en_US_POSIX`
    /// formatter in the injected calendar's zone, so tests stay pinned.
    private static func editedPhrase(_ modified: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(modified, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(modified, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: modified)
    }
}
