import Foundation
@testable import MustardKit

/// Shared `RedirectServing` stub for the OAuth/calendar tests (BAK-71 dedup).
/// Replaces the near-duplicate `StubServer` (GoogleAuthSessionTests) and
/// `StubServer2` (GoogleCalendarServiceTests): returns a fixed port and a canned
/// redirect result without any socket plumbing.
final class StubRedirectServer: RedirectServing {
    let port: Int
    let result: RedirectResult

    init(port: Int = 6000, result: RedirectResult = RedirectResult(code: "code", state: "s")) {
        self.port = port
        self.result = result
    }

    func start() throws -> Int { port }
    func awaitCode(timeout: TimeInterval) async throws -> RedirectResult { result }
    func stop() {}
}
