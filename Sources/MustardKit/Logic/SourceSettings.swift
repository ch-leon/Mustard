import Foundation

/// Per-source configuration. Generalises the single vault sweep into N sources.
/// (Gmail/inbox-specific fields — allow-list, pull repo — land with `InboxIngest`.)
public struct SourceConfig: Codable, Equatable, Identifiable {
    public var id: SourceID
    public var enabled: Bool
    public var intervalHours: Double
    public var workingDirectory: String

    public init(id: SourceID, enabled: Bool = true, intervalHours: Double = 0, workingDirectory: String = "") {
        self.id = id
        self.enabled = enabled
        self.intervalHours = intervalHours
        self.workingDirectory = workingDirectory
    }
}

/// Per-source runtime state. `lastSweptAt` is **scheduling** state (kept separate
/// from ingestion-window state, which windowed sources add later — see the spec).
public struct SourceState: Codable, Equatable, Identifiable {
    public var id: SourceID
    public var lastSweptAt: Date?
    public var lastError: String?

    public init(id: SourceID, lastSweptAt: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.lastSweptAt = lastSweptAt
        self.lastError = lastError
    }
}

/// The persisted bundle of source config + state.
public struct SourceSettings: Codable, Equatable {
    public var sources: [SourceConfig]
    public var state: [SourceState]

    public init(sources: [SourceConfig], state: [SourceState]) {
        self.sources = sources
        self.state = state
    }

    /// Replace (or append) the state entry for a source id.
    public mutating func upsertState(_ s: SourceState) {
        if let i = state.firstIndex(where: { $0.id == s.id }) { state[i] = s }
        else { state.append(s) }
    }
}

/// Loads/saves `SourceSettings` as a Codable JSON blob in `UserDefaults`
/// (light, matching the current settings style — ADR-0001 defers a SwiftData
/// settings model). `migrate` is pure for testing.
public enum SourceSettingsStore {
    public static let key = "sourceSettings"

    public static func load(_ defaults: UserDefaults = .standard) -> SourceSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SourceSettings.self, from: data)
    }

    public static func save(_ settings: SourceSettings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    /// Migrate the legacy single-vault keys (`vaultPath`, `sweepIntervalHours`,
    /// `lastSweptAt`) into per-source settings without losing manual-sweep behaviour.
    public static func migrate(vaultPath: String, sweepIntervalHours: Double, lastSweptAt: Date?) -> SourceSettings {
        SourceSettings(
            sources: [SourceConfig(id: .vault, enabled: true, intervalHours: sweepIntervalHours, workingDirectory: vaultPath)],
            state: [SourceState(id: .vault, lastSweptAt: lastSweptAt)]
        )
    }
}
