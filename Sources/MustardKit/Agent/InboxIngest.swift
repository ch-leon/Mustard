import Foundation

/// Mac-side consumer of the local routine's output: reads grounded recommendation
/// files (`<workingDirectory>/_recs/*.json`) the routine wrote locally and decodes them
/// into `SourceProposal`s for the shared insert pipeline. Pure local file read.
public enum InboxIngest {
    /// `proposals` are the successfully decoded recs; `skippedCount` is how many
    /// `.json` files in `_recs/` were rejected (malformed JSON, or missing
    /// `sourceEventID` so they can't be deduped) — so a caller can tell "nothing new"
    /// apart from "N files were silently unreadable."
    public struct Result: Sendable {
        public let proposals: [SourceProposal]
        public let skippedCount: Int
    }

    /// Decode every well-formed rec in `<workingDirectory>/_recs/*.json`, counting
    /// non-decodable or identity-less `.json` files as skipped rather than dropping
    /// them without a trace.
    public static func read(in workingDirectory: String) -> Result {
        let recsDir = URL(fileURLWithPath: workingDirectory).appendingPathComponent("_recs")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recsDir, includingPropertiesForKeys: nil
        ) else { return Result(proposals: [], skippedCount: 0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var skipped = 0
        let proposals = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> SourceProposal? in
                guard let data = try? Data(contentsOf: url),
                      let proposal = try? decoder.decode(SourceProposal.self, from: data),
                      !proposal.sourceEventID.isEmpty else {
                    skipped += 1
                    return nil
                }
                return proposal
            }
        return Result(proposals: proposals, skippedCount: skipped)
    }

    /// Convenience wrapper for callers that only need the decoded proposals.
    /// Prefer `read(in:)` for anything user-facing (see `AgentService.ingestInbox`).
    public static func readRecs(in workingDirectory: String) -> [SourceProposal] {
        read(in: workingDirectory).proposals
    }
}
