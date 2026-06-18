import Foundation

/// Mac-side consumer of the local routine's output: reads grounded recommendation
/// files (`<workingDirectory>/_recs/*.json`) the routine wrote locally and decodes them
/// into `SourceProposal`s for the shared insert pipeline. Pure local file read.
public enum InboxIngest {
    /// Decode every well-formed rec in `<workingDirectory>/_recs/*.json`. Skips
    /// non-JSON, malformed JSON, and any rec missing `sourceEventID` (can't dedupe it).
    public static func readRecs(in workingDirectory: String) -> [SourceProposal] {
        let recsDir = URL(fileURLWithPath: workingDirectory).appendingPathComponent("_recs")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recsDir, includingPropertiesForKeys: nil
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> SourceProposal? in
                guard let data = try? Data(contentsOf: url),
                      let proposal = try? decoder.decode(SourceProposal.self, from: data),
                      !proposal.sourceEventID.isEmpty else { return nil }
                return proposal
            }
    }
}
