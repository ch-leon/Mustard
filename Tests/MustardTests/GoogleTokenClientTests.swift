import XCTest
@testable import MustardKit

final class GoogleTokenClientTests: XCTestCase {
    func testExchangeBodyContainsFields() {
        let body = GoogleTokenClient.exchangeBody(
            code: "the-code", clientId: "cid", clientSecret: "secret",
            redirectURI: "http://127.0.0.1:5000", verifier: "ver")
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=the-code"))
        XCTAssertTrue(body.contains("code_verifier=ver"))
        XCTAssertTrue(body.contains("client_secret=secret"))
    }

    func testExchangeParsesToken() async throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let client = GoogleTokenClient(transport: { _ in (Data(json.utf8), 200) })
        let token = try await client.exchange(
            code: "c", pkce: PKCE(verifier: "v"),
            redirectURI: "http://127.0.0.1:1", credentials: .init(clientId: "i", clientSecret: "s"))
        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(token.refreshToken, "RT")
    }

    func testRefreshPreservesRefreshToken() async throws {
        let json = #"{"access_token":"AT2","expires_in":3600}"#   // no refresh_token in refresh response
        let client = GoogleTokenClient(transport: { _ in (Data(json.utf8), 200) })
        let token = try await client.refresh(refreshToken: "RT", credentials: .init(clientId: "i", clientSecret: "s"))
        XCTAssertEqual(token.accessToken, "AT2")
        XCTAssertEqual(token.refreshToken, "RT")
    }

    func testInvalidGrantThrows() async {
        let json = #"{"error":"invalid_grant"}"#
        let client = GoogleTokenClient(transport: { _ in (Data(json.utf8), 400) })  // Google returns 400
        do {
            _ = try await client.refresh(refreshToken: "RT", credentials: .init(clientId: "i", clientSecret: "s"))
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? GoogleAuthError, .invalidGrant) }
    }

    func testNon2xxWithoutErrorBodyThrowsServer() async {
        let client = GoogleTokenClient(transport: { _ in (Data("oops".utf8), 500) })
        do {
            _ = try await client.refresh(refreshToken: "RT", credentials: .init(clientId: "i", clientSecret: "s"))
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? GoogleAuthError, .server("token status 500")) }
    }
}
