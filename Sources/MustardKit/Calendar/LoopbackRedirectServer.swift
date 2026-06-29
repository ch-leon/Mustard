import Foundation
import Network

/// Captures the single OAuth redirect on a loopback port. The socket plumbing is a
/// thin shell (build-verified); `parseRedirect` is the pure, unit-tested seam.
public protocol RedirectServing {
    func start() throws -> Int                                   // bound port
    func awaitCode(timeout: TimeInterval) async throws -> String
    func stop()
}

public final class LoopbackRedirectServer: RedirectServing {
    private var listener: NWListener?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var resolved = false

    public init() {}

    /// Resolve the pending `awaitCode` continuation exactly once, from any thread.
    /// Guards against a double inbound connection and against the timeout racing the
    /// redirect — whichever arrives first wins; the rest are no-ops.
    private func resolve(_ result: Result<String, Error>) {
        lock.lock()
        guard !resolved else { lock.unlock(); return }
        resolved = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        switch result {
        case .success(let code): cont?.resume(returning: code)
        case .failure(let err): cont?.resume(throwing: err)
        }
    }

    public static func parseRedirect(query: String) -> Result<String, GoogleAuthError> {
        let items = URLComponents(string: "http://x?\(query)")?.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(code)
        }
        if let err = items.first(where: { $0.name == "error" })?.value {
            return .failure(err == "access_denied" ? .denied : .server(err))
        }
        return .failure(.missingCode)
    }

    public func start() throws -> Int {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let sem = DispatchSemaphore(value: 0)
        var boundPort = 0
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: boundPort = Int(listener.port?.rawValue ?? 0); sem.signal()
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: .global())
        _ = sem.wait(timeout: .now() + 5)
        guard boundPort != 0 else { throw GoogleAuthError.portBindFailed }
        return boundPort
    }

    public func awaitCode(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.waitForRedirect() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GoogleAuthError.timeout
            }
            do {
                let code = try await group.next()!
                group.cancelAll()
                return code
            } catch {
                group.cancelAll()
                // Timeout won the race: resolve the still-pending redirect continuation
                // so it is never orphaned.
                resolve(.failure(error))
                throw error
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        resolve(.failure(GoogleAuthError.timeout))   // resolve if still pending
    }

    private func waitForRedirect() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            // Request line: "GET /?code=... HTTP/1.1"
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let query = path.contains("?") ? String(path.split(separator: "?").last ?? "") : ""
            let body = "<html><body>Mustard is connected. You can close this tab.</body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
            self.resolve(LoopbackRedirectServer.parseRedirect(query: query).mapError { $0 as Error })
        }
    }
}
