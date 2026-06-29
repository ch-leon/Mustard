import XCTest
@testable import MustardKit

private final class StubServer: RedirectServing {
    let port: Int; let result: RedirectResult
    init(port: Int, result: RedirectResult) { self.port = port; self.result = result }
    func start() throws -> Int { port }
    func awaitCode(timeout: TimeInterval) async throws -> RedirectResult { result }
    func stop() {}
}

final class GoogleAuthSessionTests: XCTestCase {
    func testConnectExchangesAndPersists() async throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let store = InMemoryTokenStore()
        var openedURL: URL?
        let session = GoogleAuthSession(
            makeServer: { StubServer(port: 5123, result: .init(code: "the-code", state: "fixed-state")) },
            tokenClient: GoogleTokenClient(transport: { _ in (Data(json.utf8), 200) }),
            store: store,
            openURL: { openedURL = $0 },
            makePKCE: { PKCE(verifier: "fixed-verifier") },
            makeState: { "fixed-state" })
        let creds = GoogleCredentials(clientId: "cid", clientSecret: "sec")
        let token = try await session.connect(credentials: creds)

        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(try store.loadToken(), token)
        XCTAssertEqual(try store.loadCredentials(), creds)
        XCTAssertEqual(openedURL?.absoluteString.contains("client_id=cid"), true)
        XCTAssertEqual(openedURL?.absoluteString.contains("state=fixed-state"), true)
        XCTAssertEqual(openedURL?.absoluteString.contains("127.0.0.1:5123"), true)
    }

    func testStateMismatchRejected() async {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let store = InMemoryTokenStore()
        let session = GoogleAuthSession(
            makeServer: { StubServer(port: 5123, result: .init(code: "the-code", state: "attacker-state")) },
            tokenClient: GoogleTokenClient(transport: { _ in (Data(json.utf8), 200) }),
            store: store,
            openURL: { _ in },
            makePKCE: { PKCE(verifier: "v") },
            makeState: { "our-state" })
        do {
            _ = try await session.connect(credentials: .init(clientId: "c", clientSecret: "s"))
            XCTFail("expected state-mismatch throw")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .server("state mismatch"))
        }
        XCTAssertNil(try store.loadToken())   // nothing persisted on mismatch
    }
}
