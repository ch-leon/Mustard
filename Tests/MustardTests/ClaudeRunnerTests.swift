import XCTest
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
}
