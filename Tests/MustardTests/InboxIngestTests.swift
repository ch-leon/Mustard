import XCTest
@testable import MustardKit

final class InboxIngestTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mustard-inbox-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_readRecs_decodesValidSkipsMalformedAndNonJSON() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let recs = dir.appendingPathComponent("_recs")
        try FileManager.default.createDirectory(at: recs, withIntermediateDirectories: true)
        let valid = """
        {"source":"gmail","project":"DL","sourceItemID":"thread-1","sourceEventID":"msg-9",
         "sourceContext":"Jira · PROJ-123","sourceURL":null,"occurredAt":null,
         "title":"Reply","body":"b","actionType":"draft_email","confidence":0.8,"reasoning":"r","draft":"Hi"}
        """
        try valid.write(to: recs.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        try "{ not json".write(to: recs.appendingPathComponent("b.json"), atomically: true, encoding: .utf8)
        try "ignore me".write(to: recs.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let out = InboxIngest.readRecs(in: dir.path)
        XCTAssertEqual(out.count, 1, "decode valid .json, skip malformed + non-json")
        XCTAssertEqual(out.first?.sourceEventID, "msg-9")
        XCTAssertEqual(out.first?.source, .gmail)
        XCTAssertEqual(out.first?.project, "DL")
    }

    func test_readRecs_missingIdentity_rejected() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let recs = dir.appendingPathComponent("_recs")
        try FileManager.default.createDirectory(at: recs, withIntermediateDirectories: true)
        // No sourceEventID → can't dedupe → reject.
        let noId = #"{"source":"gmail","project":"DL","sourceItemID":"t","sourceEventID":"","title":"x","actionType":"fyi","confidence":0.5}"#
        try noId.write(to: recs.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(InboxIngest.readRecs(in: dir.path).isEmpty)
    }

    func test_readRecs_missingDir_returnsEmpty() {
        XCTAssertTrue(InboxIngest.readRecs(in: "/nope/does/not/exist").isEmpty)
    }

    func test_readRecs_decodesLabels() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let recs = dir.appendingPathComponent("_recs")
        try FileManager.default.createDirectory(at: recs, withIntermediateDirectories: true)
        let withLabels = """
        {"source":"gmail","project":"DL","sourceItemID":"t","sourceEventID":"m",
         "sourceContext":"","sourceURL":null,"occurredAt":null,"labels":["Jira Updates","INBOX"],
         "title":"x","body":"b","actionType":"fyi","confidence":0.5,"reasoning":"r","draft":""}
        """
        try withLabels.write(to: recs.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(InboxIngest.readRecs(in: dir.path).first?.labels, ["Jira Updates", "INBOX"])
    }

    func test_readRecs_missingLabels_defaultsEmpty() throws {
        // Legacy rec JSON with no `labels` key must still decode, with labels = [].
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let recs = dir.appendingPathComponent("_recs")
        try FileManager.default.createDirectory(at: recs, withIntermediateDirectories: true)
        let legacy = """
        {"source":"gmail","project":"DL","sourceItemID":"t","sourceEventID":"m",
         "sourceContext":"","sourceURL":null,"occurredAt":null,
         "title":"x","body":"b","actionType":"fyi","confidence":0.5,"reasoning":"r","draft":""}
        """
        try legacy.write(to: recs.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(InboxIngest.readRecs(in: dir.path).first?.labels, [])
    }
}
