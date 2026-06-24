import XCTest
@testable import MustardKit

final class SourceClassifierTests: XCTestCase {
    func test_gmailWithJiraLeadingToken_isJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Jira · DLA-5280 · mentioned"), .jira)
    }

    func test_gmailWithShortcutLeadingToken_isShortcut() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Shortcut · Digital Licence · sub-task"), .shortcut)
    }

    func test_gmailWithTicketKeyOnly_fallsBackToJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Mentioned on DLA-5280"), .jira)
    }

    func test_gmailUnrelatedContext_staysGmail() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "App Store Connect · SalesBuddi · app rejected"), .gmail)
    }

    func test_gmailEmptyContext_staysGmail() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: ""), .gmail)
    }

    func test_nonGmailTransport_isNeverReclassified() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .vault, sourceContext: "Jira · DLA-1"), .vault)
    }
}
