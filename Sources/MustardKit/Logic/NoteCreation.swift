import Foundation

/// Filename + stub rules for "+" note creation (BAK-153). New notes land in the
/// project's notes/ folder; collisions get " 2", " 3"… (case-insensitive against
/// existing paths). The stub's frontmatter reserves Phase B's task_id/area fields
/// a clean landing spot (spec: Frontmatter decision #8).
public enum NoteCreation {
    /// Path-separator / colon characters are each replaced by `-` so the title
    /// can't escape `notes/` or break the path; other characters (incl. the space
    /// after `My:`) are preserved. Empty/whitespace title falls back to "Untitled"
    /// — matching `stub` so filename and heading agree.
    public static func relativePath(title: String, existing: [String]) -> String {
        let name = sanitizedName(title)
        let existingLowered = Set(existing.map { $0.lowercased() })
        // First candidate is bare; collisions escalate " 2", " 3", …
        var counter = 1
        while true {
            let candidate = counter == 1 ? "notes/\(name).md" : "notes/\(name) \(counter).md"
            if !existingLowered.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    public static func stub(title: String) -> String {
        let name = trimmedOrUntitled(title)
        return "---\ntitle: \(name)\ntags: []\n---\n\n# \(name)\n"
    }

    private static func sanitizedName(_ title: String) -> String {
        var name = trimmedOrUntitled(title)
        for separator in ["/", ":", "\\"] {
            name = name.replacingOccurrences(of: separator, with: "-")
        }
        return name
    }

    private static func trimmedOrUntitled(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
