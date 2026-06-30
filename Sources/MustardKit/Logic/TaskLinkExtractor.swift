import Foundation

/// Pulls referenced http(s) links out of a recommendation's free text so a
/// materialized task can surface them (BAK-91). Labels Shortcut / Jira by host,
/// falls back to the host; de-duplicates by absolute URL, first occurrence wins.
public enum TaskLinkExtractor {
    public static func referencedLinks(in texts: [String?]) -> [TaskLink] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var seen = Set<String>()
        var out: [TaskLink] = []
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let url = match?.url, let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return }
                let key = url.absoluteString
                guard seen.insert(key).inserted else { return }
                out.append(TaskLink(label: label(for: url), url: key))
            }
        }
        return out
    }

    static func label(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("shortcut.com") { return "Shortcut" }
        if host.contains("atlassian.net") || host.contains("jira") { return "Jira" }
        return host.isEmpty ? "Link" : host
    }
}
