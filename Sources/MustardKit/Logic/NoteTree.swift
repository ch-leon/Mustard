import Foundation

public struct NoteTreeLeaf: Equatable, Identifiable {
    public let relativePath: String
    public let title: String
    public var id: String { relativePath }
    public var filename: String { (relativePath as NSString).lastPathComponent }

    public init(relativePath: String, title: String) {
        self.relativePath = relativePath
        self.title = title
    }
}

public struct NoteTreeFolder: Equatable, Identifiable {
    public let path: String            // "" for root, "guides", "guides/deep"
    public var name: String { path.isEmpty ? "" : (path as NSString).lastPathComponent }
    public var subfolders: [NoteTreeFolder]
    public var notes: [NoteTreeLeaf]
    public var id: String { path }

    public init(path: String, subfolders: [NoteTreeFolder] = [], notes: [NoteTreeLeaf] = []) {
        self.path = path
        self.subfolders = subfolders
        self.notes = notes
    }
}

/// Pure path-list → folder tree for the Notes sidebar (BAK-149), plus the
/// filename/title filter box. Folders and notes sorted case-insensitively.
public enum NoteTree {
    /// Group a project's `(relativePath, title)` list into a nested folder tree.
    /// Folders sorted case-insensitively by name; notes case-insensitively by title
    /// within each folder.
    public static func build(_ notes: [(relativePath: String, title: String)]) -> NoteTreeFolder {
        let root = MutableFolder(path: "")
        for note in notes {
            let components = (note.relativePath as NSString).pathComponents
            guard components.last != nil else { continue }
            let folderComponents = components.dropLast()
            insert(root, folderComponents: Array(folderComponents),
                   leaf: NoteTreeLeaf(relativePath: note.relativePath, title: note.title))
        }
        return freeze(root)
    }

    /// Whether a query actually filters (non-empty after trimming). Single source of
    /// truth for both `filter` and the view's "force-expand while filtering" rule.
    public static func isActiveQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Depth-first filter. Inactive (trimmed-empty) query returns the tree unchanged;
    /// otherwise keeps leaves whose `title` OR `filename` case-insensitively contains
    /// the query, and keeps folders that retain any descendant leaf.
    public static func filter(_ root: NoteTreeFolder, query: String) -> NoteTreeFolder {
        guard isActiveQuery(query) else { return root }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return prune(root, query: trimmed) ?? NoteTreeFolder(path: root.path)
    }

    // MARK: - Build helpers

    private final class MutableFolder {
        let path: String
        var subfolders: [MutableFolder] = []
        var notes: [NoteTreeLeaf] = []
        init(path: String) { self.path = path }
    }

    private static func insert(_ root: MutableFolder, folderComponents: [String],
                               leaf: NoteTreeLeaf) {
        var current = root
        var prefix = ""
        for component in folderComponents {
            prefix = prefix.isEmpty ? component : "\(prefix)/\(component)"
            if let existing = current.subfolders.first(where: { $0.path == prefix }) {
                current = existing
            } else {
                let child = MutableFolder(path: prefix)
                current.subfolders.append(child)
                current = child
            }
        }
        current.notes.append(leaf)
    }

    private static func freeze(_ folder: MutableFolder) -> NoteTreeFolder {
        let subfolders = folder.subfolders
            .map(freeze)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let notes = folder.notes
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return NoteTreeFolder(path: folder.path, subfolders: subfolders, notes: notes)
    }

    // MARK: - Filter helpers

    /// Returns a pruned copy, or nil if this folder retains no descendant leaf.
    private static func prune(_ folder: NoteTreeFolder, query: String) -> NoteTreeFolder? {
        let keptNotes = folder.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.filename.localizedCaseInsensitiveContains(query)
        }
        let keptSubfolders = folder.subfolders.compactMap { prune($0, query: query) }
        if keptNotes.isEmpty && keptSubfolders.isEmpty { return nil }
        return NoteTreeFolder(path: folder.path, subfolders: keptSubfolders, notes: keptNotes)
    }
}
