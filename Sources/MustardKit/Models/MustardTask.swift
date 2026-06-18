import Foundation
import SwiftData

@Model
public final class MustardTask {
    /// Stable id for drag-and-drop transfer (PersistentIdentifier isn't Transferable).
    public var uid: String = UUID().uuidString
    public var title: String = ""
    public var notes: String = ""
    public var statusRaw: String = TaskStatus.inbox.rawValue
    public var ownerRaw: String = TaskOwner.me.rawValue
    public var scheduledAt: Date?
    /// When scheduled: `false` = planned for the day (flows in the week list);
    /// `true` = anchored to a specific time on the week's time axis.
    public var isTimed: Bool = false
    public var estimateMinutes: Int = 30
    public var createdAt: Date = Date.now
    public var completedAt: Date?
    public var list: TaskList?
    public var priorityRaw: String = TaskPriority.normal.rawValue
    public var dueAt: Date?
    public var recurrenceRaw: String?
    public var tags: [String] = []
    public var blockedReason: String = ""
    public var recurredFrom: String?
    public var autoCompleted: Bool = false
    public var parent: MustardTask?
    @Relationship(deleteRule: .nullify, inverse: \MustardTask.parent)
    public var subtasks: [MustardTask]? = []

    // Provenance — set when a task is harvested from an external source (e.g. a
    // meeting note). All defaulted/optional so the CloudKit schema stays additive.
    /// `"manual"` for user-created, `"meeting"` for harvested meeting tasks.
    public var source: String = "manual"
    /// Source location — for meeting tasks, the note path relative to the vault root.
    public var sourceURL: String?
    /// Human subtitle for the row (e.g. the meeting title + date).
    public var sourceContext: String = ""
    /// Stable identity from `MeetingTaskParser.originKey` — dedup + line locator.
    public var originKey: String?

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    public var owner: TaskOwner {
        get { TaskOwner(rawValue: ownerRaw) ?? .me }
        set { ownerRaw = newValue.rawValue }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    public var recurrence: Recurrence? {
        get { recurrenceRaw.flatMap(Recurrence.init(rawValue:)) }
        set { recurrenceRaw = newValue?.rawValue }
    }

    public var isBlocked: Bool {
        !blockedReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// (completed, total) over direct subtasks — drives the "0/1" header.
    public var subtaskProgress: (done: Int, total: Int) {
        let subs = subtasks ?? []
        return (subs.filter { $0.status == .done }.count, subs.count)
    }

    public init(title: String = "", owner: TaskOwner = .me, scheduledAt: Date? = nil) {
        self.title = title
        self.ownerRaw = owner.rawValue
        self.scheduledAt = scheduledAt
        self.createdAt = .now
    }

    /// Mark done, stamping completion time, and cascade-complete open subtasks
    /// (recursively). Idempotent. Subtasks completed this way are flagged
    /// `autoCompleted`; the task you call this on is not.
    public func markDone(now: Date = .now) {
        status = .done
        completedAt = now
        for child in subtasks ?? [] where child.status.isOpen {
            child.autoCompleted = true
            child.markDone(now: now)
        }
    }
}
