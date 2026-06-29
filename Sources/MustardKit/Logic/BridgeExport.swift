import Foundation

public enum BridgeExport {
    public struct RouteTarget: Equatable { public let workingDir: String; public let project: String
        public init(workingDir: String, project: String) { self.workingDir = workingDir; self.project = project } }
    public struct Write: Equatable { public let workingDir: String; public let order: AgentWorkOrder }
    public struct Cancel: Equatable { public let workingDir: String; public let uid: String }
    public struct Plan: Equatable { public let writes: [Write]; public let cancels: [Cancel] }

    private static let exportStages: Set<TaskStage> = [.forAgent, .queued]

    /// `route` maps a task to its KB target (nil = unroutable → skipped).
    /// `liveOutboxUIDs` = uids with a live (non-archived) outbox file, keyed by workingDir.
    public static func plan(
        tasks: [MustardTask],
        route: (MustardTask) -> RouteTarget?,
        liveOutboxUIDs: [String: Set<String>],
        now: Date
    ) -> Plan {
        var writes: [Write] = []
        var activeByDir: [String: Set<String>] = [:]
        for t in tasks where exportStages.contains(t.stage) {
            guard let target = route(t) else { continue }
            activeByDir[target.workingDir, default: []].insert(t.uid)
            let live = liveOutboxUIDs[target.workingDir] ?? []
            if !live.contains(t.uid) {
                writes.append(Write(workingDir: target.workingDir, order: order(for: t, target: target, now: now)))
            }
        }
        var cancels: [Cancel] = []
        for (dir, uids) in liveOutboxUIDs {
            let active = activeByDir[dir] ?? []
            for uid in uids.sorted() where !active.contains(uid) {
                cancels.append(Cancel(workingDir: dir, uid: uid))
            }
        }
        return Plan(writes: writes, cancels: cancels)
    }

    static func order(for t: MustardTask, target: RouteTarget, now: Date) -> AgentWorkOrder {
        AgentWorkOrder(
            uid: t.uid,
            mode: t.stage == .forAgent ? "prep" : "execute",
            actionType: t.actionType?.rawValue ?? "",
            title: t.title, body: t.notes,
            area: t.list?.area?.name ?? "",
            project: target.project,
            sourceContext: t.sourceContext,
            links: t.links, createdAt: now)
    }
}
