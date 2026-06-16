import XCTest
@testable import MustardKit

final class SourceSettingsTests: XCTestCase {
    func test_migrate_legacyVaultKeys_toVaultSource() {
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let s = SourceSettingsStore.migrate(vaultPath: "/v", sweepIntervalHours: 4, lastSweptAt: when)

        XCTAssertEqual(s.sources.count, 1)
        XCTAssertEqual(s.sources.first?.id, .vault)
        XCTAssertEqual(s.sources.first?.workingDirectory, "/v")
        XCTAssertEqual(s.sources.first?.intervalHours, 4)
        XCTAssertEqual(s.state.first?.id, .vault)
        XCTAssertEqual(s.state.first?.lastSweptAt, when)
    }

    func test_migrate_neverSwept_lastSweptAtNil() {
        let s = SourceSettingsStore.migrate(vaultPath: "/v", sweepIntervalHours: 0, lastSweptAt: nil)
        XCTAssertNil(s.state.first?.lastSweptAt)
    }

    func test_codableRoundTrip() throws {
        let s = SourceSettings(
            sources: [SourceConfig(id: .vault, enabled: true, intervalHours: 24, workingDirectory: "/v")],
            state: [SourceState(id: .vault, lastSweptAt: Date(timeIntervalSince1970: 100), lastError: "boom")]
        )
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SourceSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func test_saveLoad_throughUserDefaults() {
        let name = "mustard-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let s = SourceSettings(
            sources: [SourceConfig(id: .vault, enabled: true, intervalHours: 1, workingDirectory: "/v")],
            state: []
        )
        SourceSettingsStore.save(s, to: suite)
        XCTAssertEqual(SourceSettingsStore.load(suite), s)
    }

    func test_load_absent_returnsNil() {
        let name = "mustard-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        XCTAssertNil(SourceSettingsStore.load(suite))
    }

    func test_upsertState_keyedByProject_notClobbered() {
        var s = SourceSettings(sources: [], state: [SourceState(id: .vault, project: "DL", lastSweptAt: nil)])
        s.upsertState(SourceState(id: .vault, project: "Sandvik", lastSweptAt: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(s.state.count, 2, "a different project is a distinct state entry, not a clobber")
        s.upsertState(SourceState(id: .vault, project: "DL", lastSweptAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(s.state.count, 2, "same (id, project) updates in place")
        XCTAssertEqual(s.state.first { $0.project == "DL" }?.lastSweptAt, Date(timeIntervalSince1970: 200))
    }

    func test_loadOrMigrate_present_loadsExisting() {
        let name = "mustard-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        SourceSettingsStore.save(
            SourceSettings(sources: [SourceConfig(id: .vault, project: "SB", workingDirectory: "/sb")], state: []),
            to: suite)
        XCTAssertEqual(SourceSettingsStore.loadOrMigrate(suite).sources.first?.project, "SB")
    }

    func test_loadOrMigrate_absent_migratesLegacyKeysAndPersists() {
        let name = "mustard-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        suite.set("/Users/x/DL-Knowledge-Base", forKey: "vaultPath")
        suite.set(4.0, forKey: "sweepIntervalHours")
        let s = SourceSettingsStore.loadOrMigrate(suite)
        XCTAssertEqual(s.sources.first?.project, "DL-Knowledge-Base")
        XCTAssertEqual(s.sources.first?.workingDirectory, "/Users/x/DL-Knowledge-Base")
        XCTAssertEqual(s.sources.first?.intervalHours, 4)
        XCTAssertNotNil(SourceSettingsStore.load(suite), "migration should persist so next load is stable")
    }
}
