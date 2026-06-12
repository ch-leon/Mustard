import Foundation

/// Prompt + parser for the vault-source triage sweep.
public enum VaultSweep {
    public static let prompt = """
    You are reviewing a personal Obsidian knowledge base to recommend actionable tasks.
    Look at the notes in this directory: recent changes, stale items, open loops, gaps.
    Recommend up to 5 concrete, actionable tasks that would move this knowledge base's
    owner forward.

    Respond with ONLY a JSON array, no prose, in this exact shape:
    [{"title": "short imperative title", "body": "1-3 sentences: what and why", "action_type": "vault_note"}]
    """

    public struct Proposal: Equatable {
        public let title: String
        public let body: String
        public let actionType: String
    }

    /// Extracts the first JSON array from model output (code-fence tolerant).
    public static func parse(_ text: String) -> [Proposal] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"), start < end else { return [] }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.prefix(5).compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            return Proposal(
                title: title,
                body: item["body"] as? String ?? "",
                actionType: item["action_type"] as? String ?? "vault_note"
            )
        }
    }

    public static func executePrompt(title: String, body: String) -> String {
        """
        Execute this task against the knowledge base in the current directory.
        If it is a research/summary task, produce the deliverable as text.
        If it asks for note changes, make them.

        Task: \(title)

        \(body)

        End your response with a concise summary of what you did and any output produced.
        """
    }
}
