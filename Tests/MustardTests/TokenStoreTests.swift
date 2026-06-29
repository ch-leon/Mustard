import XCTest
@testable import MustardKit

final class TokenStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemoryTokenStore()
        let token = GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 100))
        let creds = GoogleCredentials(clientId: "cid", clientSecret: "sec")
        try store.saveToken(token)
        try store.saveCredentials(creds)
        XCTAssertEqual(try store.loadToken(), token)
        XCTAssertEqual(try store.loadCredentials(), creds)
    }

    func testClearTokenLeavesCredentials() throws {
        let store = InMemoryTokenStore()
        try store.saveToken(GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: .now))
        try store.saveCredentials(GoogleCredentials(clientId: "c", clientSecret: "s"))
        try store.clearToken()
        XCTAssertNil(try store.loadToken())
        XCTAssertNotNil(try store.loadCredentials())
    }
}
