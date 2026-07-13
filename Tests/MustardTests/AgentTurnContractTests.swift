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

    func test_decodesValidOutcomeSpecificFields() throws {
        let needsInput = #"{"outcome":"needs_input","message":"Need detail","questions":["Which version?"],"summary":"","artifacts":[],"retryDisposition":"none"}"#
        let failed = #"{"outcome":"failed","message":"Could not continue","questions":[],"summary":"","artifacts":[],"retryDisposition":"safe","errorCategory":"network"}"#
        let connected = #"{"outcome":"requires_connected_worker","message":"Needs Shortcut","questions":[],"summary":"","artifacts":[],"retryDisposition":"none","connectedCapability":"shortcut"}"#

        XCTAssertEqual(try AgentTurnContract.decode(needsInput).outcome, .needsInput)
        XCTAssertEqual(try AgentTurnContract.decode(failed).errorCategory, "network")
        XCTAssertEqual(try AgentTurnContract.decode(connected).connectedCapability, "shortcut")
    }

    func test_rejectsMissingOrBlankOutcomeSpecificFields() {
        let needsInputCases = [
            #"{"outcome":"needs_input","message":"Need detail","questions":[],"summary":"","artifacts":[],"retryDisposition":"none"}"#,
            #"{"outcome":"needs_input","message":"Need detail","questions":["  "],"summary":"","artifacts":[],"retryDisposition":"none"}"#,
        ]
        let failedCases = [
            #"{"outcome":"failed","message":"Failed","questions":[],"summary":"","artifacts":[],"retryDisposition":"none"}"#,
            #"{"outcome":"failed","message":"Failed","questions":[],"summary":"","artifacts":[],"retryDisposition":"none","errorCategory":" \n "}"#,
        ]
        let connectedCases = [
            #"{"outcome":"requires_connected_worker","message":"Blocked","questions":[],"summary":"","artifacts":[],"retryDisposition":"none"}"#,
            #"{"outcome":"requires_connected_worker","message":"Blocked","questions":[],"summary":"","artifacts":[],"retryDisposition":"none","connectedCapability":"  "}"#,
        ]

        for json in needsInputCases + failedCases + connectedCases {
            XCTAssertThrowsError(try AgentTurnContract.decode(json), json)
        }
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
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        XCTAssertTrue(text.contains("A missing skill is not a reason to decline."))
        XCTAssertTrue(text.contains("Never send email, post messages, purchase, publish, delete external data, or take another irreversible outward action."))
        XCTAssertTrue(text.contains("Every completed task returns to Mustard Needs Review."))
        XCTAssertTrue(text.contains("Return only the JSON object required by the supplied schema."))
        XCTAssertTrue(text.contains("Mustard task UID is the stable idempotency key for outward artifact creation."))
        XCTAssertTrue(text.contains("Before creating a Shortcut or Jira artifact, search for an existing artifact carrying that key; reuse and verify it instead of creating a duplicate during retries or recovery."))
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
        XCTAssertNotNil(schema["allOf"], "schema should advertise outcome-specific requirements")
    }
}
