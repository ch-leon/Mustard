import XCTest
@testable import MustardKit

final class SourceProposalTests: XCTestCase {
    func test_vaultProposal_mapsToSourceProposalWithStableIdentity() {
        let p = VaultSweep.Proposal(
            title: "Email Bob", body: "about the X migration",
            actionType: "draft_email", confidence: 0.8,
            reasoning: "he asked", draft: "Hi Bob,"
        )

        let sp = SourceProposal(vault: p, project: "DL")

        XCTAssertEqual(sp.source, .vault)
        XCTAssertEqual(sp.title, "Email Bob")
        XCTAssertEqual(sp.actionType, "draft_email")
        XCTAssertEqual(sp.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(sp.draft, "Hi Bob,")
        XCTAssertFalse(sp.sourceEventID.isEmpty, "vault proposals must carry a stable event id")
        // Deterministic across constructions — required for dedupe across repeated sweeps.
        XCTAssertEqual(SourceProposal(vault: p, project: "DL").sourceEventID, sp.sourceEventID)
    }

    func test_vaultProposal_distinctContentGivesDistinctIdentity() {
        let a = VaultSweep.Proposal(title: "A", body: "one", actionType: "vault_note",
                                    confidence: 0.5, reasoning: "", draft: "")
        let b = VaultSweep.Proposal(title: "B", body: "two", actionType: "vault_note",
                                    confidence: 0.5, reasoning: "", draft: "")
        XCTAssertNotEqual(SourceProposal(vault: a, project: "DL").sourceEventID,
                          SourceProposal(vault: b, project: "DL").sourceEventID)
    }

    // Multi-project isolation: the identity must be project-qualified so the same
    // note text in two different KBs can never collide in dedupe.
    func test_vaultProposal_sameContentDifferentProject_distinctIdentity() {
        let p = VaultSweep.Proposal(title: "Status Dashboard", body: "weekly rollup",
                                    actionType: "vault_note", confidence: 0.5, reasoning: "", draft: "x")
        let dl = SourceProposal(vault: p, project: "DL")
        let sandvik = SourceProposal(vault: p, project: "Sandvik")
        XCTAssertEqual(dl.project, "DL")
        XCTAssertEqual(sandvik.project, "Sandvik")
        XCTAssertNotEqual(dl.sourceEventID, sandvik.sourceEventID,
                          "identical note content in different KBs must not share identity")
        XCTAssertNotEqual(dl.sourceItemID, sandvik.sourceItemID)
    }

    func test_vaultProposal_sameContentSameProject_stableIdentity() {
        let p = VaultSweep.Proposal(title: "Status Dashboard", body: "weekly rollup",
                                    actionType: "vault_note", confidence: 0.5, reasoning: "", draft: "x")
        XCTAssertEqual(SourceProposal(vault: p, project: "DL").sourceEventID,
                       SourceProposal(vault: p, project: "DL").sourceEventID)
    }
}
