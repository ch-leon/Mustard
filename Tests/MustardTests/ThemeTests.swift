import XCTest
@testable import MustardKit

/// Locks the single confidence-threshold source of truth (BAK-98).
/// Canonical tiers: ≥0.7 high (green), ≥0.5 medium (amber), else low (red).
/// Before this, `RecommendationDetailView` and `AgentConsoleView` used a ≥0.4
/// amber cutoff while the board card used ≥0.5 — this test pins the unified set.
final class ThemeTests: XCTestCase {
    func test_confidenceTier_high_atOrAbove70() {
        XCTAssertEqual(Theme.confidenceTier(0.70), .high)
        XCTAssertEqual(Theme.confidenceTier(0.85), .high)
        XCTAssertEqual(Theme.confidenceTier(1.0), .high)
    }

    func test_confidenceTier_medium_between50and70() {
        XCTAssertEqual(Theme.confidenceTier(0.50), .medium)
        XCTAssertEqual(Theme.confidenceTier(0.60), .medium)
        XCTAssertEqual(Theme.confidenceTier(0.699), .medium)
    }

    func test_confidenceTier_low_below50() {
        // 0.40 and 0.49 are LOW under the canonical threshold — this is the drift
        // the unification fixes (two views previously coloured 0.4–0.49 amber).
        XCTAssertEqual(Theme.confidenceTier(0.49), .low)
        XCTAssertEqual(Theme.confidenceTier(0.40), .low)
        XCTAssertEqual(Theme.confidenceTier(0.0), .low)
    }
}
