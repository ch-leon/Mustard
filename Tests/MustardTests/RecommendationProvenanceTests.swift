import XCTest
import SwiftData
@testable import MustardKit

final class RecommendationProvenanceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, CalendarEvent.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func test_provenanceFields_defaultNil() {
        let rec = Recommendation(title: "x")
        XCTAssertNil(rec.sourceItemID)
        XCTAssertNil(rec.sourceEventID)
        XCTAssertNil(rec.occurredAt)
    }

    func test_originalSource_defaultNil() {
        XCTAssertNil(Recommendation(title: "x").originalSource)
    }

    func test_originalSource_roundTrip() throws {
        let ctx = try makeContext()
        let rec = Recommendation(title: "From email", source: "gmail")
        rec.originalSource = "Hi Leon — for Monday's workshop…"
        ctx.insert(rec)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Recommendation>()).first?.originalSource,
                       "Hi Leon — for Monday's workshop…")
    }

    func test_provenanceFields_roundTrip() throws {
        let ctx = try makeContext()
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let rec = Recommendation(title: "From email", source: "gmail")
        rec.sourceItemID = "thread-1"
        rec.sourceEventID = "msg-9"
        rec.occurredAt = when
        ctx.insert(rec)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Recommendation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.sourceItemID, "thread-1")
        XCTAssertEqual(fetched.first?.sourceEventID, "msg-9")
        XCTAssertEqual(fetched.first?.occurredAt, when)
    }
}
