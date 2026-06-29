import XCTest
@testable import MustardKit

final class FileBridgeIOTests: XCTestCase {
    private var dir: String!
    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "bridge-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    func test_write_list_then_cancel() throws {
        let io = FileBridgeIO()
        let o = AgentWorkOrder(uid: "u1", mode: "execute", actionType: "ticket_write", title: "t",
            body: "b", area: "Digital Licence", project: "DL", sourceContext: "", links: [],
            createdAt: Date(timeIntervalSince1970: 1))
        try io.writeWorkOrder(o, workingDir: dir)
        XCTAssertEqual(io.liveOutboxUIDs(workingDir: dir), ["u1"])
        try io.cancelWorkOrder(uid: "u1", workingDir: dir)
        XCTAssertTrue(io.liveOutboxUIDs(workingDir: dir).isEmpty)
    }

    func test_readResults_thenArchive() throws {
        let io = FileBridgeIO()
        let resultsDir = dir + "/" + BridgeFolders.results
        try FileManager.default.createDirectory(atPath: resultsDir, withIntermediateDirectories: true)
        let json = #"{"uid":"u1","mode":"execute","status":"done"}"#
        try json.write(toFile: resultsDir + "/u1.json", atomically: true, encoding: .utf8)

        let read = io.readResults(workingDir: dir)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].result.uid, "u1")

        try io.archiveResult(read[0].path, workingDir: dir)
        XCTAssertTrue(io.readResults(workingDir: dir).isEmpty)              // gone from results/
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/" + BridgeFolders.resultsDone + "/u1.json"))
    }
}
