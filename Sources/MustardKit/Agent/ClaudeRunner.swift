import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct ClaudeResult: Sendable {
    public let ok: Bool
    /// Result text on success, error description on failure.
    public let text: String
    /// True when the failure looks like a usage/rate limit.
    public let rateLimited: Bool
    /// True when a zero-exit run's stdout wasn't the expected `{result,is_error}` JSON
    /// shape, so `text` is raw fallback stdout rather than a parsed `result` field. Lets
    /// callers detect "claude ran but we couldn't parse its output" instead of silently
    /// treating unparsed prose as a fully-understood success.
    public let unparsed: Bool

    public init(ok: Bool, text: String, rateLimited: Bool = false, unparsed: Bool = false) {
        self.ok = ok
        self.text = text
        self.rateLimited = rateLimited
        self.unparsed = unparsed
    }
}

/// (prompt, workingDirectory) → result. Injected so tests use a stub.
public typealias ClaudeRun = @Sendable (String, String) async -> ClaudeResult

public enum ClaudeRunner {
#if os(macOS)
    /// Wall-clock budget for a single `claude -p` invocation before it's killed and
    /// treated as a failure. Real headless runs can take minutes, so the default is
    /// generous; `ClaudeRunnerTests` dials this down to exercise the timeout path
    /// quickly, which is why this is a settable `static var` rather than a constant.
    public static var timeoutSeconds: TimeInterval = 600

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

    /// Lock-protected box for state shared between a pipe's `readabilityHandler`
    /// (called on a background thread by the runloop) and the code that reads the
    /// result after `waitUntilExit()` returns.
    private final class Locked<Value>: @unchecked Sendable {
        private var value: Value
        private let lock = NSLock()
        init(_ value: Value) { self.value = value }
        func withLock<R>(_ body: (inout Value) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
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

                // Drain both pipes concurrently. Reading stdout to EOF before touching
                // stderr (the old approach) deadlocks if the child fills the ~64KB
                // stderr pipe buffer while stdout is still open — the child blocks
                // writing stderr, we're blocked reading stdout, forever.
                let stdoutBuffer = Locked(Data())
                let stderrBuffer = Locked(Data())
                out.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        stdoutBuffer.withLock { $0.append(chunk) }
                    }
                }
                err.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        stderrBuffer.withLock { $0.append(chunk) }
                    }
                }

                let timedOut = Locked(false)
                let timeoutItem = DispatchWorkItem {
                    guard process.isRunning else { return }
                    timedOut.withLock { $0 = true }
                    process.terminate() // SIGTERM
                    // SIGTERM isn't guaranteed to be honored (e.g. a trapping shell);
                    // force the issue shortly after so a hung run can't linger forever.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

                process.waitUntilExit()
                timeoutItem.cancel()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil

                if timedOut.withLock({ $0 }) {
                    continuation.resume(returning: ClaudeResult(
                        ok: false, text: "claude timed out after \(Int(timeoutSeconds))s"))
                    return
                }

                let stdout = String(data: stdoutBuffer.withLock { $0 }, encoding: .utf8) ?? ""
                let stderr = String(data: stderrBuffer.withLock { $0 }, encoding: .utf8) ?? ""

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
                    continuation.resume(returning: ClaudeResult(
                        ok: true, text: stdout.trimmingCharacters(in: .whitespacesAndNewlines), unparsed: true))
                } else {
                    let text = "claude exited \(process.terminationStatus)\n\(stderr)"
                    continuation.resume(returning: ClaudeResult(ok: false, text: text, rateLimited: limited(stderr)))
                }
            }
        }
    }
#else
    /// The agent shells out to the `claude` CLI, which runs on the Mac only (ADR-0003).
    /// The iOS companion never executes agent work — it reads/writes shared data. This
    /// stub keeps `ClaudeRunner.run` available so `AgentService` compiles for iOS.
    public static let run: ClaudeRun = { _, _ in
        ClaudeResult(ok: false, text: "The agent runs on the Mac only.")
    }
#endif
}
