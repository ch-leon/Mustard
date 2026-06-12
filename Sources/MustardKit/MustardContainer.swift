import Foundation
import SwiftData

/// Builds the app's persistent ModelContainer at a Mustard-owned location
/// (avoids colliding with other unsandboxed apps' default.store).
public enum MustardContainer {
    public static func make() -> ModelContainer {
        let dir = URL.applicationSupportDirectory.appending(path: "Mustard", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: dir.appending(path: "mustard.store"))
        do {
            return try ModelContainer(
                for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, configurations: config
            )
        } catch {
            fatalError("Could not open Mustard store: \(error)")
        }
    }
}
