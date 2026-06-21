import Foundation

/// Pure resolver: a task's client Area → the KB working directory the agent should
/// run `claude -p` in when you delegate that task. Routes by Area (Leon's choice,
/// 2026-06-22) so delegated work runs in-project. Reverses `MeetingTaskSync`'s
/// folder→Area map, prefers an explicitly configured source for that KB, and falls
/// back to `<workVaultRoot>/<subVault>`. Nil when the Area maps to no KB.
public enum AreaRouter {
    public static func workingDirectory(
        forArea areaName: String?,
        sources: [SourceConfig],
        workVaultRoot: String,
        areaMap: [String: String] = MeetingTaskSync.defaultAreaMap
    ) -> String? {
        guard let areaName, !areaName.isEmpty else { return nil }
        // Reverse the folder→Area map: "Digital Licence" → "DL".
        guard let subVault = areaMap.first(where: { $0.value == areaName })?.key else { return nil }

        // Prefer an explicitly configured source for this KB (keeps sweep + delegation
        // running in the same directory for a given project).
        if let configured = sources.first(where: { $0.project == subVault && !$0.workingDirectory.isEmpty }) {
            return configured.workingDirectory
        }

        guard !workVaultRoot.isEmpty else { return nil }
        return URL(fileURLWithPath: workVaultRoot, isDirectory: true)
            .appendingPathComponent(subVault).path
    }
}
