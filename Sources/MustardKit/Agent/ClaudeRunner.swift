import Foundation

public struct ClaudeResult: Sendable {
    public let ok: Bool
    /// Result text on success, error description on failure.
    public let text: String
    /// True when the failure looks like a usage/rate limit.
    public let rateLimited: Bool

    public init(ok: Bool, text: String, rateLimited: Bool = false) {
        self.ok = ok
        self.text = text
        self.rateLimited = rateLimited
    }
}

/// (prompt, workingDirectory) → result. Injected so tests use a stub.
public typealias ClaudeRun = @Sendable (String, String) async -> ClaudeResult

public enum ClaudeRunner {
    /// Env for the spawned CLI: drop ANTHROPIC_ and CLAUDE vars so a run
    /// started from inside a Claude Code session (which injects a proxy
    /// base URL the child can't authenticate against) still uses the CLI's
    /// own subscription login.
    static func cleanEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("ANTHROPIC_") && !key.hasPrefix("CLAUDE")
        }
    }

    static func binaryPath() -> String {
        if let override = ProcessInfo.processInfo.environment["MUSTARD_CLAUDE_BIN"] {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in ["\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "claude"
    }

    /// Runs `claude -p` headless against the logged-in subscription.
    /// stdin is /dev/null — the CLI waits on an open pipe otherwise.
    public static let run: ClaudeRun = { prompt, cwd in
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath())
                process.arguments = ["-p", prompt, "--output-format", "json"]
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                process.environment = cleanEnvironment()
                process.standardInput = FileHandle.nullDevice
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ClaudeResult(ok: false, text: String(describing: error)))
                    return
                }
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()

                func limited(_ s: String) -> Bool {
                    s.range(of: "rate.?limit|usage limit", options: .regularExpression, range: nil, locale: nil) != nil
                        || s.localizedCaseInsensitiveContains("usage limit")
                }

                struct CLIOutput: Decodable {
                    let result: String?
                    let is_error: Bool?
                }
                if let data = stdout.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(CLIOutput.self, from: data) {
                    if parsed.is_error == true {
                        let text = parsed.result ?? "claude reported an error"
                        continuation.resume(returning: ClaudeResult(ok: false, text: text, rateLimited: limited(text)))
                    } else {
                        continuation.resume(returning: ClaudeResult(ok: true, text: parsed.result ?? ""))
                    }
                } else if process.terminationStatus == 0 {
                    continuation.resume(returning: ClaudeResult(ok: true, text: stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let text = "claude exited \(process.terminationStatus)\n\(stderr)"
                    continuation.resume(returning: ClaudeResult(ok: false, text: text, rateLimited: limited(stderr)))
                }
            }
        }
    }
}
