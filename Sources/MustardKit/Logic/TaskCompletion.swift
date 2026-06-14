import Foundation
import SwiftData

/// The single choke-point for the "done" direction: cascade-complete subtasks
/// (via markDone) and, if the task recurs, insert a fresh next instance. Used by
/// every completion path (Today, the detail sheet, Board drag-to-Done) so the
/// automation fires uniformly. Not pure (needs a context); its pieces — markDone
/// and RecurrenceEngine.nextInstance — are unit-tested individually.
public enum TaskCompletion {
    public static func complete(_ task: MustardTask, in context: ModelContext, now: Date = .now) {
        let next = RecurrenceEngine.nextInstance(of: task, now: now)
        task.markDone(now: now)
        if let next { context.insert(next) }
    }
}
