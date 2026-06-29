import Foundation

/// File operations the bridge needs; injected so the service is testable with a stub.
public protocol BridgeIO {
    func liveOutboxUIDs(workingDir: String) -> Set<String>
    func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws
    func cancelWorkOrder(uid: String, workingDir: String) throws
    func readResults(workingDir: String) -> [(result: AgentResult, path: String)]
    func archiveResult(_ path: String, workingDir: String) throws
}

public struct FileBridgeIO: BridgeIO {
    public init() {}
    private var fm: FileManager { .default }

    public func liveOutboxUIDs(workingDir: String) -> Set<String> {
        let p = workingDir + "/" + BridgeFolders.outbox
        guard let files = try? fm.contentsOfDirectory(atPath: p) else { return [] }
        return Set(files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
    }

    public func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws {
        let dir = workingDir + "/" + BridgeFolders.outbox
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try BridgeCoding.encoder.encode(order).write(to: URL(fileURLWithPath: dir + "/\(order.uid).json"))
    }

    public func cancelWorkOrder(uid: String, workingDir: String) throws {
        let path = workingDir + "/" + BridgeFolders.outbox + "/\(uid).json"
        if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
    }

    public func readResults(workingDir: String) -> [(result: AgentResult, path: String)] {
        let p = workingDir + "/" + BridgeFolders.results
        guard let files = try? fm.contentsOfDirectory(atPath: p) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let path = p + "/" + name
            guard let data = fm.contents(atPath: path),
                  let r = try? BridgeCoding.decoder.decode(AgentResult.self, from: data),
                  !r.uid.isEmpty else { return nil }
            return (r, path)
        }
    }

    public func archiveResult(_ path: String, workingDir: String) throws {
        let doneDir = workingDir + "/" + BridgeFolders.resultsDone
        try fm.createDirectory(atPath: doneDir, withIntermediateDirectories: true)
        let dest = doneDir + "/" + (path as NSString).lastPathComponent
        if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
        try fm.moveItem(atPath: path, toPath: dest)
    }
}
