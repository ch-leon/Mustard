import Foundation
import SwiftData

/// File-system boundary for the meeting-task sync, injected so the decision
/// logic can be unit-tested against an in-memory map (no disk).
public protocol MeetingVaultIO {
    /// Meeting-note paths relative to the vault root.
    func meetingNotePaths() -> [String]
    func read(_ relativePath: String) -> String?
    func write(_ relativePath: String, _ contents: String) throws
    /// Write-only safety copy taken before any edit (the vault blocks deletes).
    func snapshot(_ relativePath: String, _ contents: String) throws
}

/// Result of an import pass — the not-silent record surfaced in the sweep digest.
public struct ImportDigest: Equatable {
    public var imported = 0
    public var completedFromVault = 0
    public var syncedToVault = 0
    public var clients: Set<String> = []

    public var summary: String {
        "imported \(imported) meeting task\(imported == 1 ? "" : "s") "
            + "(\(clients.count) client\(clients.count == 1 ? "" : "s"))"
    }
}

/// Bridges Leon's curated meeting-note checklists into Mustard's task store and
/// reflects completion back. Import is deterministic and idempotent (dedup by
/// `originKey`); write-back snapshots before editing and touches only the one line.
@MainActor
public final class MeetingTaskSync {
    /// vault-root folder → Mustard Area name. `nonisolated` so pure helpers
    /// (e.g. `AreaRouter`) can read this immutable map without main-actor isolation.
    public nonisolated static let defaultAreaMap: [String: String] = [
        "DL": "Digital Licence",
        "SB": "Sales Buddi",
        "Sandvik": "Sandvik",
        "Code Heroes": "Code Heroes",
    ]

    private let context: ModelContext
    private let io: MeetingVaultIO
    private let areaMap: [String: String]
    private let fallbackArea: String
    private var listCache: [String: TaskList] = [:]

    public init(
        context: ModelContext,
        io: MeetingVaultIO,
        areaMap: [String: String] = MeetingTaskSync.defaultAreaMap,
        fallbackArea: String = "Code Heroes"
    ) {
        self.context = context
        self.io = io
        self.areaMap = areaMap
        self.fallbackArea = fallbackArea
    }

    // MARK: Import (vault → Mustard)

    @discardableResult
    public func importTasks(now: Date = .now) -> ImportDigest {
        var digest = ImportDigest()
        var byKey = existingMeetingTasksByKey()

        for path in io.meetingNotePaths() {
            guard let text = io.read(path) else { continue }
            let subtitle = meetingSubtitle(text: text, path: path)
            for parsed in MeetingTaskParser.parse(text, notePath: path) {
                if let task = byKey[parsed.originKey] {
                    if parsed.isDone && task.status.isOpen {
                        // Line ticked in the vault while the task was open → vault won.
                        task.markDone(now: now)
                        digest.completedFromVault += 1
                    } else if !parsed.isDone && task.status == .done {
                        // Completed in Mustard but the note line is still open → write back.
                        if completeInVault(task, now: task.completedAt ?? now) {
                            digest.syncedToVault += 1
                        }
                    }
                    // otherwise already reconciled → dedup no-op.
                } else {
                    let task = makeTask(parsed, subtitle: subtitle, now: now)
                    context.insert(task)
                    byKey[parsed.originKey] = task
                    digest.imported += 1
                    digest.clients.insert(clientName(forNotePath: path))
                }
            }
        }
        return digest
    }

    private func makeTask(_ p: ParsedMeetingTask, subtitle: String, now: Date) -> MustardTask {
        let task = MustardTask(title: p.title, owner: .me)
        task.status = .inbox
        task.source = "meeting"
        task.sourceURL = p.notePath
        task.sourceContext = subtitle
        task.originKey = p.originKey
        task.dueAt = p.due
        task.list = defaultList(forClient: clientName(forNotePath: p.notePath))
        // Already ticked in the vault → import as done, don't resurrect it open.
        if p.isDone { task.markDone(now: now) }
        return task
    }

    // MARK: Write-back (Mustard → vault)

    /// On completing a meeting task, snapshot the source note and rewrite its
    /// `- [ ]` line to `- [x] ✅ <today>`. Returns `false` (and writes nothing)
    /// if the line can't be located — note moved/edited — so callers can flag it.
    @discardableResult
    public func completeInVault(_ task: MustardTask, now: Date = .now) -> Bool {
        guard task.source == "meeting",
              let key = task.originKey,
              let path = task.sourceURL,
              let contents = io.read(path) else { return false }

        var lines = contents.components(separatedBy: "\n")
        guard let idx = lines.firstIndex(where: { line in
            MeetingTaskParser.isCheckbox(line.trimmingCharacters(in: .whitespaces))
                && MeetingTaskParser.originKey(notePath: path, line: line) == key
        }) else { return false }

        do { try io.snapshot(path, contents) } catch { return false }
        lines[idx] = Self.tick(lines[idx], doneISO: Self.isoDay(now))
        do { try io.write(path, lines.joined(separator: "\n")) } catch { return false }
        return true
    }

    /// Flip `[ ]`→`[x]` and add `✅ <date>`, inserting before a trailing block id
    /// if present. No-op on the date if the line is already completed.
    static func tick(_ line: String, doneISO: String) -> String {
        var l = line
        if let r = l.range(of: #"\[ \]"#, options: .regularExpression) {
            l.replaceSubrange(r, with: "[x]")
        }
        if l.range(of: #"✅\s*\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil { return l }
        let marker = "✅ \(doneISO)"
        if let m = l.range(of: #"\s*\^[\w-]+\s*$"#, options: .regularExpression) {
            let blockId = l[m].trimmingCharacters(in: .whitespaces)
            l.replaceSubrange(m, with: " \(marker) \(blockId)")
        } else {
            l = l.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) + " \(marker)"
        }
        return l
    }

    // MARK: Helpers

    private func existingMeetingTasksByKey() -> [String: MustardTask] {
        let all = (try? context.fetch(FetchDescriptor<MustardTask>())) ?? []
        var byKey: [String: MustardTask] = [:]
        // `hasPrefix` so backlog-pruned tasks (source `meeting:archived`) keep
        // suppressing re-import of their now-stale lines — without them the old
        // lines would re-flood as fresh tasks. Write-back stays gated on the exact
        // `"meeting"` source below, so archived tasks never tick the vault.
        for t in all where t.source.hasPrefix("meeting") {
            if let k = t.originKey { byKey[k] = t }
        }
        return byKey
    }

    private func clientName(forNotePath path: String) -> String {
        let root = path.split(separator: "/").first.map(String.init) ?? ""
        return areaMap[root] ?? fallbackArea
    }

    /// The note's first `# ` heading, falling back to the file name — the row subtitle.
    private func meetingSubtitle(text: String, path: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        return (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    }

    /// The default list for a client Area, creating the Area + list on first use.
    private func defaultList(forClient name: String) -> TaskList {
        if let cached = listCache[name] { return cached }
        if let area = ((try? context.fetch(FetchDescriptor<Area>())) ?? []).first(where: { $0.name == name }) {
            let list = (area.lists ?? []).first ?? {
                let l = TaskList(name: name, area: area); context.insert(l); return l
            }()
            listCache[name] = list
            return list
        }
        let area = Area(name: name)
        context.insert(area)
        let list = TaskList(name: name, area: area)
        context.insert(list)
        listCache[name] = list
        return list
    }

    private static func isoDay(_ date: Date) -> String { isoFormatter.string(from: date) }
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
