import XCTest
@testable import MustardKit

final class LoopbackRedirectServerTests: XCTestCase {
    func testParsesCodeAndState() {
        let r = LoopbackRedirectServer.parseRedirect(query: "code=abc123&state=xyz&scope=cal")
        XCTAssertEqual(try? r.get(), RedirectResult(code: "abc123", state: "xyz"))
    }
    func testParsesCodeWithoutState() {
        let r = LoopbackRedirectServer.parseRedirect(query: "code=abc123")
        XCTAssertEqual(try? r.get(), RedirectResult(code: "abc123", state: nil))
    }
    func testAccessDeniedMapsToDenied() {
        let r = LoopbackRedirectServer.parseRedirect(query: "error=access_denied")
        guard case .failure(.denied) = r else { return XCTFail("expected .denied") }
    }
    func testOtherErrorMapsToServer() {
        let r = LoopbackRedirectServer.parseRedirect(query: "error=invalid_scope")
        guard case .failure(.server("invalid_scope")) = r else { return XCTFail("expected .server") }
    }
    func testNoCodeMapsToMissingCode() {
        let r = LoopbackRedirectServer.parseRedirect(query: "state=x")
        guard case .failure(.missingCode) = r else { return XCTFail("expected .missingCode") }
    }
}
