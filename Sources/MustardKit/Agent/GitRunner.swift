import Foundation

/// Minimal best-effort `git pull` for refreshing a KB repo's `_recs/` (cloud scout
/// output) before `InboxIngest`. Fast-forward only; failures are ignored — ingest
/// then just reads whatever is already on disk. Runs off the main actor.
public enum GitRunner {
    public static func pull(cwd: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "-C", cwd, "pull", "--ff-only", "--quiet"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    // best-effort: ignore (offline, not a repo, auth needed, etc.)
                }
                continuation.resume()
            }
        }
    }
}
