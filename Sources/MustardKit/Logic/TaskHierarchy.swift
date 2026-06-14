import Foundation

/// Pure task-hierarchy guards, mirroring the predecessor app's server/cycleGuard.ts.
public enum TaskHierarchy {
    /// Would assigning `newParent` as the parent of `task` create a cycle?
    /// True if `newParent` is the task itself, or anywhere up `newParent`'s ancestor
    /// chain we reach `task` (or a pre-existing loop — treated as unsafe).
    public static func wouldCreateCycle(assigning newParent: MustardTask, to task: MustardTask) -> Bool {
        var cursor: MustardTask? = newParent
        var visited = Set<String>()
        while let node = cursor {
            if node === task { return true }
            if visited.contains(node.uid) { return true }
            visited.insert(node.uid)
            cursor = node.parent
        }
        return false
    }
}
