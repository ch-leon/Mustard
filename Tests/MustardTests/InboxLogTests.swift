import XCTest
@testable import MustardKit

final class InboxLogTests: XCTestCase {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func test_logURL_isUnderFiledFolder() {
        let url = InboxLog.logURL(workingDirectory: "/kb/DL")
        XCTAssertTrue(url.path.hasSuffix("/kb/DL/_filed/inbox-log.md"))
    }

    func test_entry_isDeterministic_withThreadLink() {
        let entry = InboxLog.entry(
            title: "Reply to Ruby", body: "be aware", source: "gmail",
            sourceURL: "https://x", now: utc(2026, 6, 19, 14, 32)
        )
        let expected =
            "## 2026-06-19 14:32 · gmail · Reply to Ruby\n" +
            "[thread](https://x)\n" +
            "\n" +
            "be aware\n" +
            "\n" +
            "---\n"
        XCTAssertEqual(entry, expected)
    }

    func test_entry_omitsThreadLine_whenNoURL() {
        let entry = InboxLog.entry(
            title: "Note", body: "body", source: "vault",
            sourceURL: nil, now: utc(2026, 6, 19, 9, 5)
        )
        XCTAssertFalse(entry.contains("[thread]"))
        XCTAssertTrue(entry.hasPrefix("## 2026-06-19 09:05 · vault · Note\n"))
    }
}
