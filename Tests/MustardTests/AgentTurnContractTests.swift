import Foundation
import XCTest
@testable import MustardKit

final class AgentTurnContractTests: XCTestCase {
    func test_decodesNeedsInput() throws {
        let json = #"{"outcome":"needs_input","message":"I need the version","questions":["Which version?"],"summary":"","artifacts":[],"retryDisposition":"none"}"#

        let result = try AgentTurnContract.decode(json)

        XCTAssertEqual(result.outcome, .needsInput)
        XCTAssertEqual(result.questions, ["Which version?"])
    }

    func test_decodesCompletedArtifact() throws {
        let json = #"{"outcome":"completed","message":"Created it","questions":[],"summary":"Created Shortcut 123","artifacts":[{"label":"Shortcut","url":"https://app.shortcut.com/x/123"}],"retryDisposition":"none"}"#

        let result = try AgentTurnContract.decode(json)

        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.artifacts.first?.label, "Shortcut")
    }

    func test_rejectsUnknownOutcomeAndProse() {
        let otherwiseCompleteUnknownOutcome = #"{"outcome":"done","message":"Done","questions":[],"summary":"Done","artifacts":[],"retryDisposition":"none"}"#

        XCTAssertThrowsError(try AgentTurnContract.decode(otherwiseCompleteUnknownOutcome))
        XCTAssertThrowsError(try AgentTurnContract.decode("looks good"))
    }

    func test_decodeRejectsUnknownTopLevelAndArtifactProperties() {
        let unknownTopLevel = #"{"outcome":"completed","message":"Done","questions":[],"summary":"Done","artifacts":[],"retryDisposition":"none","surprise":true}"#
        let unknownArtifact = #"{"outcome":"completed","message":"Done","questions":[],"summary":"Done","artifacts":[{"label":"File","url":"file:///tmp/result","surprise":true}],"retryDisposition":"none"}"#

        XCTAssertThrowsError(try AgentTurnContract.decode(unknownTopLevel))
        XCTAssertThrowsError(try AgentTurnContract.decode(unknownArtifact))
    }

    func test_workerContractContainsHardSafetyRules() throws {
        let text = try AgentTurnContract.workerContract()

        XCTAssertTrue(text.contains("Never send email"))
        XCTAssertTrue(text.contains("Needs Review"))
        XCTAssertTrue(text.contains("missing skill is not a reason to decline"))
    }

    func test_schemaRequiresStrictResultAndArtifactShapes() throws {
        let data = Data(AgentTurnContract.jsonSchema.utf8)
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let outcome = try XCTUnwrap(properties["outcome"] as? [String: Any])
        let retryDisposition = try XCTUnwrap(properties["retryDisposition"] as? [String: Any])
        let artifacts = try XCTUnwrap(properties["artifacts"] as? [String: Any])
        let artifactItems = try XCTUnwrap(artifacts["items"] as? [String: Any])

        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(
            schema["required"] as? [String],
            ["outcome", "message", "questions", "summary", "artifacts", "retryDisposition"]
        )
        XCTAssertEqual(
            outcome["enum"] as? [String],
            ["completed", "needs_input", "failed", "cancelled", "requires_connected_worker"]
        )
        XCTAssertEqual(
            retryDisposition["enum"] as? [String],
            ["none", "safe", "backoff", "uncertain"]
        )
        XCTAssertEqual(artifactItems["additionalProperties"] as? Bool, false)
        XCTAssertEqual(artifactItems["required"] as? [String], ["label", "url"])
    }
}
