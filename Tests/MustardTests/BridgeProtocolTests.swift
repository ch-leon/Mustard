import XCTest
@testable import MustardKit

final class BridgeProtocolTests: XCTestCase {
    func test_workOrder_roundTrips() throws {
        let o = AgentWorkOrder(
            uid: "u1", mode: "execute", actionType: "ticket_write", title: "T", body: "B",
            area: "Digital Licence", project: "DL", sourceContext: "ctx",
            links: [TaskLink(label: "Jira", url: "https://x")], createdAt: Date(timeIntervalSince1970: 1))
        let data = try BridgeCoding.encoder.encode(o)
        let back = try BridgeCoding.decoder.decode(AgentWorkOrder.self, from: data)
        XCTAssertEqual(o, back)
    }

    func test_result_decodes_withMissingOptionals() throws {
        let json = #"{"uid":"u1","mode":"execute","status":"done"}"#.data(using: .utf8)!
        let r = try BridgeCoding.decoder.decode(AgentResult.self, from: json)
        XCTAssertEqual(r.uid, "u1"); XCTAssertEqual(r.status, "done")
        XCTAssertNil(r.links); XCTAssertNil(r.error)
    }

    func test_folderConstants() {
        XCTAssertEqual(BridgeFolders.outbox, "_agent/outbox")
        XCTAssertEqual(BridgeFolders.outboxDone, "_agent/outbox/done")
        XCTAssertEqual(BridgeFolders.results, "_agent/results")
        XCTAssertEqual(BridgeFolders.resultsDone, "_agent/results/done")
    }
}
