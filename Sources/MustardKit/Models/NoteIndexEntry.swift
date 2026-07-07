import Foundation
import SwiftData

/// SwiftData mirror of one vault `.md` file (Notes Phase A, BAK-148). The file is
/// the source of truth; this row exists for fast search/backlinks and the future
/// mobile read-only view (N2). Keyed (project, relativePath) — project is the KB
/// folder name (matches SourceConfig.project), NOT SourceID (see spec addendum #1).
@Model
public final class NoteIndexEntry {
    public var project: String = ""
    public var relativePath: String = ""
    public var title: String = ""
    public var tags: [String] = []
    public var lastModified: Date = Date.distantPast
    public var forwardLinks: [String] = []
    public var contentSnapshot: String = ""

    public init(project: String = "", relativePath: String = "", title: String = "",
                tags: [String] = [], lastModified: Date = .distantPast,
                forwardLinks: [String] = [], contentSnapshot: String = "") {
        self.project = project; self.relativePath = relativePath; self.title = title
        self.tags = tags; self.lastModified = lastModified
        self.forwardLinks = forwardLinks; self.contentSnapshot = contentSnapshot
    }
}
