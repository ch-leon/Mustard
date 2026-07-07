import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import MustardKit

/// Exercises the real Process-spawn path against a stub binary
/// (MUSTARD_CLAUDE_BIN), covering env-scrub, closed stdin, JSON parsing.
final class ClaudeRunnerTests: XCTestCase {
    private var stubPath: String!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mustard-tests")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appending(path: "fake-claude.sh")
        let script = """
        #!/bin/zsh
        echo '{"type":"result","is_error":false,"result":"stub says hi"}'
        """
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stub.path)
        stubPath = stub.path
        setenv("MUSTARD_CLAUDE_BIN", stubPath, 1)
    }

    override func tearDown() {
        unsetenv("MUSTARD_CLAUDE_BIN")
    }

    func test_run_spawnsBinaryAndParsesResultJSON() async {
        let result = await ClaudeRunner.run("any prompt", "/tmp")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "stub says hi")
    }

    func test_run_errorJSONIsFailure() async throws {
        let errStub = FileManager.default.temporaryDirectory
            .appending(path: "mustard-tests/fake-claude-err.sh")
        try """
        #!/bin/zsh
        echo '{"is_error":true,"result":"usage limit reached"}'
        """.write(to: errStub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: errStub.path)
        setenv("MUSTARD_CLAUDE_BIN", errStub.path, 1)

        let result = await ClaudeRunner.run("any", "/tmp")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.rateLimited)
    }

    func test_cleanEnvironment_stripsSessionVars() {
        setenv("ANTHROPIC_BASE_URL", "http://proxy", 1)
        setenv("CLAUDECODE", "1", 1)
        defer { unsetenv("ANTHROPIC_BASE_URL"); unsetenv("CLAUDECODE") }
        let env = ClaudeRunner.cleanEnvironment()
        XCTAssertNil(env["ANTHROPIC_BASE_URL"])
        XCTAssertNil(env["CLAUDECODE"])
        XCTAssertNotNil(env["PATH"])
    }

    // MARK: - zero-exit non-JSON stdout is flagged, not silently accepted

    func test_run_zeroExitNonJSONStdout_isFlaggedUnparsed() async throws {
        let stub = FileManager.default.temporaryDirectory
            .appending(path: "mustard-tests/fake-claude-prose.sh")
        try """
        #!/bin/zsh
        echo 'I looked around but found nothing worth flagging.'
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stub.path)
        setenv("MUSTARD_CLAUDE_BIN", stub.path, 1)

        let result = await ClaudeRunner.run("any", "/tmp")
        XCTAssertTrue(result.ok, "a zero-exit run is still a success even if unparsed")
        XCTAssertTrue(result.unparsed, "fallback raw-stdout path must be flagged as unparsed")
    }

    func test_run_wellFormedJSONResult_isNotFlaggedUnparsed() async {
        // fake-claude.sh (setUp) emits the expected {result,is_error} shape.
        let result = await ClaudeRunner.run("any prompt", "/tmp")
        XCTAssertFalse(result.unparsed)
    }

    // MARK: - concurrent pipe drain (large stderr must not deadlock stdout)

    func test_run_largeStderrDoesNotDeadlockStdoutDrain() async throws {
        let stub = FileManager.default.temporaryDirectory
            .appending(path: "mustard-tests/fake-claude-noisy.sh")
        // >64KB of stderr before the stdout JSON — the old sequential
        // read-stdout-then-stderr implementation deadlocks on this.
        try """
        #!/bin/zsh
        for i in {1..4000}; do
          echo "noisy stderr line $i padded padded padded padded padded padded" 1>&2
        done
        echo '{"is_error":false,"result":"stub says hi after noise"}'
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stub.path)
        setenv("MUSTARD_CLAUDE_BIN", stub.path, 1)

        let result = await ClaudeRunner.run("any", "/tmp")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "stub says hi after noise")
    }

    // MARK: - timeout

    func test_run_timesOut_returnsTimeoutError_andKillsTheProcess() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mustard-tests")
        let pidFile = dir.appending(path: "hung-pid-\(UUID().uuidString).txt")
        let stub = dir.appending(path: "fake-claude-hung.sh")
        // A busy-loop (not `sleep`, which forks a grandchild) so the pid we
        // capture is the one the timeout must actually terminate.
        try """
        #!/bin/zsh
        echo $$ > \(pidFile.path)
        while true; do :; done
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stub.path)
        setenv("MUSTARD_CLAUDE_BIN", stub.path, 1)

        let originalTimeout = ClaudeRunner.timeoutSeconds
        ClaudeRunner.timeoutSeconds = 1
        defer { ClaudeRunner.timeoutSeconds = originalTimeout }

        let result = await ClaudeRunner.run("any", "/tmp")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.text.contains("timed out"), "expected a clear timeout message, got: \(result.text)")

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = pid_t(pidText) ?? 0
        XCTAssertGreaterThan(pid, 0)
        XCTAssertNotEqual(kill(pid, 0), 0, "the hung process must be dead once run() returns")
    }
}
