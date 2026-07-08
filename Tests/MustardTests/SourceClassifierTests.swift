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

    // MARK: label-driven classification (labels are ground truth over content)
    func test_gmailWithJiraLabel_isJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "", labels: ["Jira"]), .jira)
    }

    func test_gmailWithJiraUpdatesLabel_isJira() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "", labels: ["Jira Updates"]), .jira)
    }

    func test_gmailWithShortcutNotificationsLabel_isShortcut() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "", labels: ["Shortcut Notifications"]), .shortcut)
    }

    /// The bug case: a human reply carries labels but none are Jira/Shortcut, yet its
    /// body/context mentions a ticket key. Labels present → content regex must NOT fire.
    func test_gmailLabelsPresentButNotSourcey_ticketKeyInContentStaysGmail() {
        XCTAssertEqual(
            SourceClassifier.logicalSource(
                transport: .gmail, sourceContext: "Reply from Timothé · re DLA-5598", labels: ["INBOX"]),
            .gmail)
    }

    func test_gmailNonSourceyLabels_staysGmail() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "", labels: ["Sales Buddi"]), .gmail)
    }

    func test_nonGmailTransport_labelsIgnored() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .vault, sourceContext: "", labels: ["Jira"]), .vault)
    }

    /// No labels captured (legacy rec) → old provenance-text heuristics still apply.
    func test_noLabels_fallsBackToLegacyHeuristics() {
        XCTAssertEqual(SourceClassifier.logicalSource(transport: .gmail, sourceContext: "Mentioned on DLA-5280", labels: []), .jira)
    }
}
