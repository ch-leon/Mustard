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

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    public var owner: TaskOwner {
        get { TaskOwner(rawValue: ownerRaw) ?? .me }
        set { ownerRaw = newValue.rawValue }
    }

    public init(title: String = "", owner: TaskOwner = .me, scheduledAt: Date? = nil) {
        self.title = title
        self.ownerRaw = owner.rawValue
        self.scheduledAt = scheduledAt
        self.createdAt = .now
    }

    /// Mark done, stamping completion time. Idempotent.
    public func markDone(now: Date = .now) {
        status = .done
        completedAt = now
    }
}
