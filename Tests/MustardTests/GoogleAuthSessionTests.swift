import XCTest
@testable import MustardKit

private final class StubServer: RedirectServing {
    let port: Int; let code: String
    init(port: Int, code: String) { self.port = port; self.code = code }
    func start() throws -> Int { port }
    func awaitCode(timeout: TimeInterval) async throws -> String { code }
    func stop() {}
}

final class GoogleAuthSessionTests: XCTestCase {
    func testConnectExchangesAndPersists() async throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let store = InMemoryTokenStore()
        var openedURL: URL?
        let session = GoogleAuthSession(
            makeServer: { StubServer(port: 5123, code: "the-code") },
            tokenClient: GoogleTokenClient(transport: { _ in Data(json.utf8) }),
            store: store,
            openURL: { openedURL = $0 },
            makePKCE: { PKCE(verifier: "fixed-verifier") })
        let creds = GoogleCredentials(clientId: "cid", clientSecret: "sec")
        let token = try await session.connect(credentials: creds)

        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(try store.loadToken(), token)
        XCTAssertEqual(try store.loadCredentials(), creds)
        XCTAssertEqual(openedURL?.absoluteString.contains("client_id=cid"), true)
        XCTAssertEqual(openedURL?.absoluteString.contains("127.0.0.1:5123"), true)
    }
}
