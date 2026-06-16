import XCTest
@testable import MustardKit

final class SourceProposalTests: XCTestCase {
    func test_vaultProposal_mapsToSourceProposalWithStableIdentity() {
        let p = VaultSweep.Proposal(
            title: "Email Bob", body: "about the X migration",
            actionType: "draft_email", confidence: 0.8,
            reasoning: "he asked", draft: "Hi Bob,"
        )

        let sp = SourceProposal(vault: p)

        XCTAssertEqual(sp.source, .vault)
        XCTAssertEqual(sp.title, "Email Bob")
        XCTAssertEqual(sp.actionType, "draft_email")
        XCTAssertEqual(sp.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(sp.draft, "Hi Bob,")
        XCTAssertFalse(sp.sourceEventID.isEmpty, "vault proposals must carry a stable event id")
        // Deterministic across constructions — required for dedupe across repeated sweeps.
        XCTAssertEqual(SourceProposal(vault: p).sourceEventID, sp.sourceEventID)
    }

    func test_vaultProposal_distinctContentGivesDistinctIdentity() {
        let a = VaultSweep.Proposal(title: "A", body: "one", actionType: "vault_note",
                                    confidence: 0.5, reasoning: "", draft: "")
        let b = VaultSweep.Proposal(title: "B", body: "two", actionType: "vault_note",
                                    confidence: 0.5, reasoning: "", draft: "")
        XCTAssertNotEqual(SourceProposal(vault: a).sourceEventID,
                          SourceProposal(vault: b).sourceEventID)
    }
}
