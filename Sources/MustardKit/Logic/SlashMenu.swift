import Foundation

/// One command in the editor's "/" menu (Craft spec 2026-07-06, Phase 2b).
public struct SlashCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let kind: Kind

    public enum Kind: Equatable { case todo, heading, linkToNote, subpage, askAgent }

    public init(id: String, title: String, icon: String, kind: Kind) {
        self.id = id
        self.title = title
        self.icon = icon
        self.kind = kind
    }
}

/// Pure query → commands for the editor's "/" menu (Craft spec, 2b), plus trigger
/// detection and the markdown each command splices. Insertions are the ONLY source
/// text this menu produces — pinned byte-exact in SlashMenuTests (markdown-as-truth:
/// `NoteDecoration` stays read-only; `BlockReorder.move` and `insertion(for:noteTitle:)`
/// are the two source-producing functions in the whole editor).
///
/// Shape mirrors `CommandBarEngine` (static item list, `items(query:)` filter) so
/// the two command surfaces stay conceptually one pattern.
public enum SlashMenu {

    private static let commands: [SlashCommand] = [
        SlashCommand(id: "todo", title: "To-do", icon: "checkmark.square", kind: .todo),
        SlashCommand(id: "heading", title: "Heading", icon: "number", kind: .heading),
        SlashCommand(id: "link", title: "Link to note", icon: "link", kind: .linkToNote),
        SlashCommand(id: "subpage", title: "Sub-page", icon: "doc.badge.plus", kind: .subpage),
        SlashCommand(id: "agent", title: "Ask the agent", icon: "sparkles", kind: .askAgent),
    ]

    /// Filter: case-insensitive PREFIX match against any whitespace-separated word
    /// of the title. Deliberately not `CommandBarEngine`'s substring-contains —
    /// with these titles, "he" would leak "Ask *the* agent" in via "the", which is
    /// exactly the wrong row two keystrokes into "heading". Word-prefix matches
    /// how a slash query is actually typed (the start of the command you mean).
    public static func items(query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }
        let lowered = query.lowercased()
        return commands.filter { command in
            command.title.split(whereSeparator: { $0.isWhitespace }).contains { word in
                word.lowercased().hasPrefix(lowered)
            }
        }
    }

    /// Non-nil (the query typed so far) when the caret sits in an active trigger:
    /// the line up to the caret must be exactly "/" + query, query containing no
    /// whitespace. "a /x" (mid-line slash) or "/x y" (query ended) is not a trigger —
    /// the menu only ever interrupts a line the user just started with "/".
    public static func activeQuery(linePrefix: String) -> String? {
        guard linePrefix.hasPrefix("/") else { return nil }
        let query = String(linePrefix.dropFirst())
        guard !query.contains(where: { $0.isWhitespace }) else { return nil }
        return query
    }

    /// Markdown to splice at line start + caret offset (UTF-16 units into `text`)
    /// after insertion. `.subpage`/`.linkToNote` interpolate the chosen/created
    /// note title. Every template is byte-pinned in SlashMenuTests.
    ///
    /// "Ask the agent" deliberately just writes an `[!agent]` callout line — plain
    /// markdown the existing vault sweep already reads on its next pass. No new
    /// AgentService plumbing; the restraint is the feature (the file stays the
    /// only contract between the editor and the agent).
    public static func insertion(for kind: SlashCommand.Kind, noteTitle: String?) -> (text: String, caretOffset: Int) {
        switch kind {
        case .todo:
            return atEnd("- [ ] ")
        case .heading:
            return atEnd("## ")
        case .linkToNote:
            if let noteTitle, !noteTitle.isEmpty {
                return atEnd("[[\(noteTitle)]]")
            }
            // Empty brackets, caret between them — the user types the target and
            // the existing resolve/create-from-dangling flows take over.
            return (text: "[[]]", caretOffset: 2)
        case .subpage:
            // The host creates the note FIRST and passes the created title back in,
            // so the link always matches the real (collision-deduped) filename.
            // "Untitled" mirrors NoteCreation's empty-title fallback.
            let title = (noteTitle?.isEmpty == false) ? noteTitle! : "Untitled"
            return atEnd("[[\(title)]]\n")
        case .askAgent:
            return atEnd("> [!agent] ")
        }
    }

    /// Caret lands after the last inserted character. UTF-16 length, because the
    /// caller adds this to an NSTextView `selectedRange` location.
    private static func atEnd(_ text: String) -> (text: String, caretOffset: Int) {
        (text: text, caretOffset: (text as NSString).length)
    }
}
