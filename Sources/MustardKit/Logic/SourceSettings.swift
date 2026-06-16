import Foundation

/// Per-source, per-project configuration. Generalises the single vault sweep into
/// N projects (one per KB). (Gmail/inbox-specific fields land with `InboxIngest`.)
public struct SourceConfig: Codable, Equatable {
    public var id: SourceID
    /// Project / knowledge base identity (the KB folder name). Distinct projects are
    /// distinct sources — keeps scheduling, dedupe, and grounding isolated per KB.
    public var project: String
    public var enabled: Bool
    public var intervalHours: Double
    public var workingDirectory: String

    public init(id: SourceID, project: String = "", enabled: Bool = true, intervalHours: Double = 0, workingDirectory: String = "") {
        self.id = id
        self.project = project
        self.enabled = enabled
        self.intervalHours = intervalHours
        self.workingDirectory = workingDirectory
    }
}

/// Per-source, per-project runtime state. `lastSweptAt` is **scheduling** state.
public struct SourceState: Codable, Equatable {
    public var id: SourceID
    public var project: String
    public var lastSweptAt: Date?
    public var lastError: String?

    public init(id: SourceID, project: String = "", lastSweptAt: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.project = project
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

    /// Replace (or append) the state entry for a `(source id, project)` pair — so
    /// advancing one KB's state never clobbers another's.
    public mutating func upsertState(_ s: SourceState) {
        if let i = state.firstIndex(where: { $0.id == s.id && $0.project == s.project }) { state[i] = s }
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
    /// Project = the vault folder name.
    public static func migrate(vaultPath: String, sweepIntervalHours: Double, lastSweptAt: Date?) -> SourceSettings {
        let project = URL(fileURLWithPath: vaultPath).lastPathComponent
        return SourceSettings(
            sources: [SourceConfig(id: .vault, project: project, enabled: true, intervalHours: sweepIntervalHours, workingDirectory: vaultPath)],
            state: [SourceState(id: .vault, project: project, lastSweptAt: lastSweptAt)]
        )
    }
}
