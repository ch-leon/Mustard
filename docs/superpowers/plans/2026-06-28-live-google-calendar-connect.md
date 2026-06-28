# Live Google Calendar Connect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **In this repo the chosen execution path is `dev-loop:execute-agent-issue`** (BAK-45), which drives implementation → `swift test`/`swift build` → fresh-context review → PR → merge-policy.

**Goal:** Wire the live Google Calendar OAuth + fetch flow so real `primary`-calendar meetings sync into `CalendarEvent` rows on top of the existing tested pure layer.

**Architecture:** New units in `Sources/MustardKit/Calendar/` follow the repo rule — pure logic is unit-tested, and network/Keychain/browser are thin injected shells. A loopback HTTP listener captures the OAuth redirect (Desktop-app flow); `GoogleCalendarService` (`@Observable`, mirrors `AgentService`) orchestrates connect/refresh/fetch and upserts into a `ModelContext`. Settings UI extends `SourceSettingsView`; `MustardApp` owns the service and pumps it from the existing 60s loop.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `Network` (`NWListener`), `Security` (Keychain), `CryptoKit` (already used). **No `Package.swift` changes** — all are system frameworks.

**Spec:** `docs/superpowers/specs/2026-06-28-live-google-calendar-connect-design.md`

---

## File structure

| File | Responsibility | New/Modify |
|------|----------------|------------|
| `Sources/MustardKit/Calendar/CalendarTypes.swift` | `GoogleAuthError`, `GoogleCredentials`, `CalendarWindow`, `HTTPTransport` | New |
| `Sources/MustardKit/Calendar/GoogleOAuth.swift` | add `Codable` to `GoogleToken` | Modify |
| `Sources/MustardKit/Calendar/LoopbackRedirectServer.swift` | `RedirectServing` protocol + `parseRedirect` (pure) + `NWListener` shell | New |
| `Sources/MustardKit/Calendar/GoogleTokenClient.swift` | form-body builders (pure) + exchange/refresh | New |
| `Sources/MustardKit/Calendar/GoogleEventsClient.swift` | events URL builder (pure) + fetch | New |
| `Sources/MustardKit/Calendar/TokenStore.swift` | `TokenStore` protocol + `InMemoryTokenStore` + `KeychainTokenStore` | New |
| `Sources/MustardKit/Calendar/CalendarSync.swift` | `upsertEvents` reconciler | New |
| `Sources/MustardKit/Calendar/GoogleAuthSession.swift` | connect orchestration | New |
| `Sources/MustardKit/Calendar/GoogleCalendarService.swift` | `@Observable` orchestrator | New |
| `Sources/MustardKit/Views/SourceSettingsView.swift` | Google Calendar settings section | Modify |
| `Sources/Mustard/MustardApp.swift` | construct + wire service into 60s loop | Modify |
| `Tests/MustardTests/*` | one test file per unit | New |

---

## Task 1: Shared types + redirect parsing

**Files:**
- Create: `Sources/MustardKit/Calendar/CalendarTypes.swift`
- Create: `Sources/MustardKit/Calendar/LoopbackRedirectServer.swift`
- Test: `Tests/MustardTests/LoopbackRedirectServerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class LoopbackRedirectServerTests: XCTestCase {
    func testParsesCode() {
        let r = LoopbackRedirectServer.parseRedirect(query: "code=abc123&scope=cal")
        XCTAssertEqual(try? r.get(), "abc123")
    }
    func testAccessDeniedMapsToDenied() {
        let r = LoopbackRedirectServer.parseRedirect(query: "error=access_denied")
        guard case .failure(.denied) = r else { return XCTFail("expected .denied") }
    }
    func testOtherErrorMapsToServer() {
        let r = LoopbackRedirectServer.parseRedirect(query: "error=invalid_scope")
        guard case .failure(.server("invalid_scope")) = r else { return XCTFail("expected .server") }
    }
    func testNoCodeMapsToMissingCode() {
        let r = LoopbackRedirectServer.parseRedirect(query: "state=x")
        guard case .failure(.missingCode) = r else { return XCTFail("expected .missingCode") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LoopbackRedirectServerTests`
Expected: FAIL — `LoopbackRedirectServer` / `GoogleAuthError` undefined.

- [ ] **Step 3: Create the shared types**

`Sources/MustardKit/Calendar/CalendarTypes.swift`:

```swift
import Foundation

public enum GoogleAuthError: Error, Equatable {
    case denied
    case missingCode
    case portBindFailed
    case timeout
    case invalidGrant
    case server(String)
    case network(String)
}

public struct GoogleCredentials: Codable, Equatable {
    public let clientId: String
    public let clientSecret: String
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

public struct CalendarWindow: Equatable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    /// Start-of-today through `days` later, in the given calendar.
    public static func rolling(from now: Date, days: Int, calendar: Calendar = .current) -> CalendarWindow {
        let startOfDay = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: startOfDay)!
        return CalendarWindow(start: startOfDay, end: end)
    }
}

/// Injectable HTTP seam: returns the response body. Non-2xx is surfaced via the body
/// (Google returns a JSON `error` field), so callers parse rather than inspect status.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> Data
```

- [ ] **Step 4: Create the redirect server (pure parse + NWListener shell)**

`Sources/MustardKit/Calendar/LoopbackRedirectServer.swift`:

```swift
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
    private var continuation: CheckedContinuation<String, Error>?
    private var resolved = false

    public init() {}

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
            let code = try await group.next()!
            group.cancelAll()
            return code
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func waitForRedirect() async throws -> String {
        try await withCheckedThrowingContinuation { cont in self.continuation = cont }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            // Request line: "GET /?code=... HTTP/1.1"
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let query = path.contains("?") ? String(path.split(separator: "?").last ?? "") : ""
            let result = LoopbackRedirectServer.parseRedirect(query: query)
            let body = "<html><body>Mustard is connected. You can close this tab.</body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
            guard !self.resolved else { return }
            self.resolved = true
            switch result {
            case .success(let code): self.continuation?.resume(returning: code)
            case .failure(let err): self.continuation?.resume(throwing: err)
            }
            self.continuation = nil
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter LoopbackRedirectServerTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Calendar/CalendarTypes.swift Sources/MustardKit/Calendar/LoopbackRedirectServer.swift Tests/MustardTests/LoopbackRedirectServerTests.swift
git commit -m "feat(bak-45): loopback redirect server + shared calendar types"
```

---

## Task 2: GoogleTokenClient (exchange + refresh)

**Files:**
- Modify: `Sources/MustardKit/Calendar/GoogleOAuth.swift` (add `Codable`)
- Create: `Sources/MustardKit/Calendar/GoogleTokenClient.swift`
- Test: `Tests/MustardTests/GoogleTokenClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class GoogleTokenClientTests: XCTestCase {
    func testExchangeBodyContainsFields() {
        let body = GoogleTokenClient.exchangeBody(
            code: "the-code", clientId: "cid", clientSecret: "secret",
            redirectURI: "http://127.0.0.1:5000", verifier: "ver")
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=the-code"))
        XCTAssertTrue(body.contains("code_verifier=ver"))
        XCTAssertTrue(body.contains("client_secret=secret"))
    }

    func testExchangeParsesToken() async throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let client = GoogleTokenClient(transport: { _ in Data(json.utf8) })
        let token = try await client.exchange(
            code: "c", pkce: PKCE(verifier: "v"),
            redirectURI: "http://127.0.0.1:1", credentials: .init(clientId: "i", clientSecret: "s"))
        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(token.refreshToken, "RT")
    }

    func testRefreshPreservesRefreshToken() async throws {
        let json = #"{"access_token":"AT2","expires_in":3600}"#   // no refresh_token in refresh response
        let client = GoogleTokenClient(transport: { _ in Data(json.utf8) })
        let token = try await client.refresh(refreshToken: "RT", credentials: .init(clientId: "i", clientSecret: "s"))
        XCTAssertEqual(token.accessToken, "AT2")
        XCTAssertEqual(token.refreshToken, "RT")
    }

    func testInvalidGrantThrows() async {
        let json = #"{"error":"invalid_grant"}"#
        let client = GoogleTokenClient(transport: { _ in Data(json.utf8) })
        do {
            _ = try await client.refresh(refreshToken: "RT", credentials: .init(clientId: "i", clientSecret: "s"))
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? GoogleAuthError, .invalidGrant) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GoogleTokenClientTests`
Expected: FAIL — `GoogleTokenClient` undefined.

- [ ] **Step 3: Add `Codable` to `GoogleToken`**

In `Sources/MustardKit/Calendar/GoogleOAuth.swift`, change the declaration:

```swift
public struct GoogleToken: Codable, Equatable {
```

(rest of `GoogleToken` unchanged.)

- [ ] **Step 4: Create `GoogleTokenClient`**

`Sources/MustardKit/Calendar/GoogleTokenClient.swift`:

```swift
import Foundation

/// HTTP for the OAuth token endpoint. Body builders are pure; the network is injected.
public struct GoogleTokenClient {
    let transport: HTTPTransport

    public init(transport: @escaping HTTPTransport = GoogleTokenClient.defaultTransport) {
        self.transport = transport
    }

    public static let defaultTransport: HTTPTransport = { req in
        try await URLSession.shared.data(for: req).0
    }

    public static func exchangeBody(code: String, clientId: String, clientSecret: String,
                                    redirectURI: String, verifier: String) -> String {
        formEncode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", clientId),
            ("client_secret", clientSecret),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
        ])
    }

    public static func refreshBody(refreshToken: String, clientId: String, clientSecret: String) -> String {
        formEncode([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientId),
            ("client_secret", clientSecret),
        ])
    }

    public func exchange(code: String, pkce: PKCE, redirectURI: String,
                         credentials: GoogleCredentials) async throws -> GoogleToken {
        let body = Self.exchangeBody(code: code, clientId: credentials.clientId,
                                     clientSecret: credentials.clientSecret,
                                     redirectURI: redirectURI, verifier: pkce.verifier)
        let data = try await post(body)
        guard let token = GoogleOAuth.parseTokenResponse(data) else { throw Self.error(from: data) }
        return token
    }

    public func refresh(refreshToken: String, credentials: GoogleCredentials) async throws -> GoogleToken {
        let body = Self.refreshBody(refreshToken: refreshToken, clientId: credentials.clientId,
                                    clientSecret: credentials.clientSecret)
        let data = try await post(body)
        guard let token = GoogleOAuth.parseTokenResponse(data) else { throw Self.error(from: data) }
        // Refresh responses omit refresh_token — carry the existing one forward.
        if token.refreshToken == nil {
            return GoogleToken(accessToken: token.accessToken, refreshToken: refreshToken, expiresAt: token.expiresAt)
        }
        return token
    }

    private func post(_ body: String) async throws -> Data {
        var req = URLRequest(url: URL(string: GoogleOAuth.tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        return try await transport(req)
    }

    static func error(from data: Data) -> GoogleAuthError {
        struct Err: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Err.self, from: data))?.error
        if code == "invalid_grant" { return .invalidGrant }
        return .server(code ?? "unexpected token response")
    }

    static func formEncode(_ pairs: [(String, String)]) -> String {
        var c = URLComponents()
        c.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.percentEncodedQuery ?? ""
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter GoogleTokenClientTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Calendar/GoogleOAuth.swift Sources/MustardKit/Calendar/GoogleTokenClient.swift Tests/MustardTests/GoogleTokenClientTests.swift
git commit -m "feat(bak-45): Google token client (exchange + refresh)"
```

---

## Task 3: GoogleEventsClient (events.list fetch)

**Files:**
- Create: `Sources/MustardKit/Calendar/GoogleEventsClient.swift`
- Test: `Tests/MustardTests/GoogleEventsClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class GoogleEventsClientTests: XCTestCase {
    func testEventsURLHasWindowAndOrdering() {
        let win = CalendarWindow(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400))
        let url = GoogleEventsClient.eventsURL(calendarId: "primary", window: win).absoluteString
        XCTAssertTrue(url.contains("/calendars/primary/events"))
        XCTAssertTrue(url.contains("singleEvents=true"))
        XCTAssertTrue(url.contains("orderBy=startTime"))
        XCTAssertTrue(url.contains("timeMin="))
        XCTAssertTrue(url.contains("timeMax="))
    }

    func testFetchParsesEvents() async throws {
        let json = #"{"items":[{"id":"e1","summary":"Standup","status":"confirmed","start":{"dateTime":"2026-06-28T09:00:00Z"},"end":{"dateTime":"2026-06-28T09:15:00Z"}}]}"#
        let client = GoogleEventsClient(transport: { _ in Data(json.utf8) })
        let events = try await client.fetch(
            accessToken: "AT", calendarId: "primary",
            window: CalendarWindow(start: .now, end: .now))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.externalId, "e1")
        XCTAssertEqual(events.first?.title, "Standup")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GoogleEventsClientTests`
Expected: FAIL — `GoogleEventsClient` undefined.

- [ ] **Step 3: Create `GoogleEventsClient`**

`Sources/MustardKit/Calendar/GoogleEventsClient.swift`:

```swift
import Foundation

/// HTTP for Google Calendar `events.list`. URL builder is pure; network is injected;
/// parsing reuses `GoogleCalendarParser`.
public struct GoogleEventsClient {
    let transport: HTTPTransport

    public init(transport: @escaping HTTPTransport = GoogleTokenClient.defaultTransport) {
        self.transport = transport
    }

    public static func eventsURL(calendarId: String, window: CalendarWindow) -> URL {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
        c.queryItems = [
            .init(name: "timeMin", value: f.string(from: window.start)),
            .init(name: "timeMax", value: f.string(from: window.end)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250"),
        ]
        return c.url!
    }

    public func fetch(accessToken: String, calendarId: String,
                      window: CalendarWindow) async throws -> [ParsedEvent] {
        var req = URLRequest(url: Self.eventsURL(calendarId: calendarId, window: window))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await transport(req)
        return GoogleCalendarParser.parseEvents(data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GoogleEventsClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Calendar/GoogleEventsClient.swift Tests/MustardTests/GoogleEventsClientTests.swift
git commit -m "feat(bak-45): Google events client (events.list fetch)"
```

---

## Task 4: TokenStore (protocol + in-memory + Keychain)

**Files:**
- Create: `Sources/MustardKit/Calendar/TokenStore.swift`
- Test: `Tests/MustardTests/TokenStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class TokenStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemoryTokenStore()
        let token = GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 100))
        let creds = GoogleCredentials(clientId: "cid", clientSecret: "sec")
        try store.saveToken(token)
        try store.saveCredentials(creds)
        XCTAssertEqual(try store.loadToken(), token)
        XCTAssertEqual(try store.loadCredentials(), creds)
    }

    func testClearTokenLeavesCredentials() throws {
        let store = InMemoryTokenStore()
        try store.saveToken(GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: .now))
        try store.saveCredentials(GoogleCredentials(clientId: "c", clientSecret: "s"))
        try store.clearToken()
        XCTAssertNil(try store.loadToken())
        XCTAssertNotNil(try store.loadCredentials())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenStoreTests`
Expected: FAIL — `InMemoryTokenStore` undefined.

- [ ] **Step 3: Create `TokenStore` + implementations**

`Sources/MustardKit/Calendar/TokenStore.swift`:

```swift
import Foundation
import Security

public protocol TokenStore {
    func saveToken(_ token: GoogleToken) throws
    func loadToken() throws -> GoogleToken?
    func clearToken() throws
    func saveCredentials(_ creds: GoogleCredentials) throws
    func loadCredentials() throws -> GoogleCredentials?
}

public final class InMemoryTokenStore: TokenStore {
    private var token: GoogleToken?
    private var creds: GoogleCredentials?
    public init() {}
    public func saveToken(_ token: GoogleToken) throws { self.token = token }
    public func loadToken() throws -> GoogleToken? { token }
    public func clearToken() throws { token = nil }
    public func saveCredentials(_ creds: GoogleCredentials) throws { self.creds = creds }
    public func loadCredentials() throws -> GoogleCredentials? { creds }
}

/// Real store: one generic-password Keychain item per key, holding JSON.
/// Build-verified + exercised by live use (the `ClaudeRunner` pattern); not unit-tested.
public final class KeychainTokenStore: TokenStore {
    private let service: String
    private let tokenKey = "google.token"
    private let credsKey = "google.credentials"

    public init(service: String = "com.mustard.google-calendar") { self.service = service }

    public func saveToken(_ token: GoogleToken) throws { try set(tokenKey, try JSONEncoder().encode(token)) }
    public func loadToken() throws -> GoogleToken? {
        guard let data = try get(tokenKey) else { return nil }
        return try JSONDecoder().decode(GoogleToken.self, from: data)
    }
    public func clearToken() throws { try delete(tokenKey) }
    public func saveCredentials(_ creds: GoogleCredentials) throws { try set(credsKey, try JSONEncoder().encode(creds)) }
    public func loadCredentials() throws -> GoogleCredentials? {
        guard let data = try get(credsKey) else { return nil }
        return try JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    private func set(_ key: String, _ data: Data) throws {
        SecItemDelete(query(key) as CFDictionary)
        var add = query(key); add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleAuthError.server("keychain write \(status)") }
    }
    private func get(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GoogleAuthError.server("keychain read \(status)") }
        return out as? Data
    }
    private func delete(_ key: String) throws { SecItemDelete(query(key) as CFDictionary) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Calendar/TokenStore.swift Tests/MustardTests/TokenStoreTests.swift
git commit -m "feat(bak-45): token store (in-memory + Keychain)"
```

---

## Task 5: Event upsert reconciler

**Files:**
- Create: `Sources/MustardKit/Calendar/CalendarSync.swift`
- Test: `Tests/MustardTests/CalendarSyncTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
@testable import MustardKit

final class CalendarSyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CalendarEvent.self, configurations: config)
        return ModelContext(container)
    }
    private func parsed(_ id: String, _ title: String, start: Date) -> ParsedEvent {
        ParsedEvent(externalId: id, title: title, start: start, end: start.addingTimeInterval(900),
                    isAllDay: false, joinURL: nil, location: nil)
    }

    func testInsertsNewEvents() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        try upsertEvents([parsed("e1", "A", start: Date(timeIntervalSince1970: 10))],
                         into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.map(\.externalId), ["e1"])
    }

    func testUpdatesExistingByExternalId() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        let t = Date(timeIntervalSince1970: 10)
        try upsertEvents([parsed("e1", "Old", start: t)], into: ctx, calendarId: "primary", window: win)
        try upsertEvents([parsed("e1", "New", start: t)], into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "New")
    }

    func testDeletesVanishedInWindow() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        let t = Date(timeIntervalSince1970: 10)
        try upsertEvents([parsed("e1", "A", start: t), parsed("e2", "B", start: t)],
                         into: ctx, calendarId: "primary", window: win)
        try upsertEvents([parsed("e1", "A", start: t)], into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.map(\.externalId), ["e1"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalendarSyncTests`
Expected: FAIL — `upsertEvents` undefined.

- [ ] **Step 3: Implement `upsertEvents`**

`Sources/MustardKit/Calendar/CalendarSync.swift`:

```swift
import Foundation
import SwiftData

/// Reconcile fetched events into `CalendarEvent` rows for one calendar + window:
/// update matches by `externalId`, insert new, delete in-window rows that vanished.
public func upsertEvents(_ parsed: [ParsedEvent], into context: ModelContext,
                         calendarId: String, window: CalendarWindow) throws {
    let lo = window.start, hi = window.end
    let descriptor = FetchDescriptor<CalendarEvent>(
        predicate: #Predicate { $0.calendarId == calendarId && $0.start >= lo && $0.start < hi })
    let existing = try context.fetch(descriptor)
    let byId = Dictionary(existing.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a })
    let incomingIds = Set(parsed.map(\.externalId))

    for p in parsed {
        if let e = byId[p.externalId] {
            e.title = p.title; e.start = p.start; e.end = p.end
            e.isAllDay = p.isAllDay; e.joinURL = p.joinURL; e.location = p.location
            e.updatedAt = .now
        } else {
            context.insert(CalendarEvent(
                externalId: p.externalId, calendarId: calendarId, title: p.title,
                start: p.start, end: p.end, isAllDay: p.isAllDay,
                joinURL: p.joinURL, location: p.location))
        }
    }
    for e in existing where !incomingIds.contains(e.externalId) { context.delete(e) }
    try context.save()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CalendarSyncTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Calendar/CalendarSync.swift Tests/MustardTests/CalendarSyncTests.swift
git commit -m "feat(bak-45): event upsert reconciler"
```

---

## Task 6: GoogleAuthSession (connect orchestration)

**Files:**
- Create: `Sources/MustardKit/Calendar/GoogleAuthSession.swift`
- Test: `Tests/MustardTests/GoogleAuthSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

private final class StubServer: RedirectServing {
    let port: Int; let code: String
    init(port: Int, code: String) { self.port = port; self.code = code }
    func start() throws -> Int { port }
    func awaitCode(timeout: TimeInterval) async throws -> String { code }
    func stop() {}
}

final class GoogleAuthSessionTests: XCTestCase {
    func testConnectExchangesAndPersists() async throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#
        let store = InMemoryTokenStore()
        var openedURL: URL?
        let session = GoogleAuthSession(
            makeServer: { StubServer(port: 5123, code: "the-code") },
            tokenClient: GoogleTokenClient(transport: { _ in Data(json.utf8) }),
            store: store,
            openURL: { openedURL = $0 },
            makePKCE: { PKCE(verifier: "fixed-verifier") })
        let creds = GoogleCredentials(clientId: "cid", clientSecret: "sec")
        let token = try await session.connect(credentials: creds)

        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(try store.loadToken(), token)
        XCTAssertEqual(try store.loadCredentials(), creds)
        XCTAssertEqual(openedURL?.absoluteString.contains("client_id=cid"), true)
        XCTAssertEqual(openedURL?.absoluteString.contains("127.0.0.1:5123"), true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GoogleAuthSessionTests`
Expected: FAIL — `GoogleAuthSession` undefined.

- [ ] **Step 3: Implement `GoogleAuthSession`**

`Sources/MustardKit/Calendar/GoogleAuthSession.swift`:

```swift
import Foundation

/// Orchestrates the OAuth connect: PKCE → loopback server → browser → code → token.
/// Every side-effecting dependency is injected, so the whole flow is unit-testable.
public struct GoogleAuthSession {
    let makeServer: () -> RedirectServing
    let tokenClient: GoogleTokenClient
    let store: TokenStore
    let openURL: (URL) -> Void
    let makePKCE: () -> PKCE
    let timeout: TimeInterval

    public init(makeServer: @escaping () -> RedirectServing,
                tokenClient: GoogleTokenClient,
                store: TokenStore,
                openURL: @escaping (URL) -> Void,
                makePKCE: @escaping () -> PKCE = { PKCE.random() },
                timeout: TimeInterval = 120) {
        self.makeServer = makeServer
        self.tokenClient = tokenClient
        self.store = store
        self.openURL = openURL
        self.makePKCE = makePKCE
        self.timeout = timeout
    }

    public func connect(credentials: GoogleCredentials) async throws -> GoogleToken {
        let pkce = makePKCE()
        let server = makeServer()
        let port = try server.start()
        defer { server.stop() }
        let redirectURI = "http://127.0.0.1:\(port)"
        openURL(GoogleOAuth.authorizationURL(clientId: credentials.clientId,
                                             redirectURI: redirectURI, pkce: pkce))
        let code = try await server.awaitCode(timeout: timeout)
        let token = try await tokenClient.exchange(code: code, pkce: pkce,
                                                   redirectURI: redirectURI, credentials: credentials)
        try store.saveCredentials(credentials)
        try store.saveToken(token)
        return token
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GoogleAuthSessionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Calendar/GoogleAuthSession.swift Tests/MustardTests/GoogleAuthSessionTests.swift
git commit -m "feat(bak-45): Google auth session (connect orchestration)"
```

---

## Task 7: GoogleCalendarService (@Observable orchestrator)

**Files:**
- Create: `Sources/MustardKit/Calendar/GoogleCalendarService.swift`
- Test: `Tests/MustardTests/GoogleCalendarServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
@testable import MustardKit

private final class StubServer2: RedirectServing {
    func start() throws -> Int { 6000 }
    func awaitCode(timeout: TimeInterval) async throws -> String { "code" }
    func stop() {}
}

@MainActor
final class GoogleCalendarServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: CalendarEvent.self, configurations: config))
    }

    private func makeService(store: TokenStore, tokenJSON: String, eventsJSON: String,
                             context: ModelContext, now: @escaping () -> Date) -> GoogleCalendarService {
        let tokenClient = GoogleTokenClient(transport: { _ in Data(tokenJSON.utf8) })
        let session = GoogleAuthSession(
            makeServer: { StubServer2() }, tokenClient: tokenClient, store: store,
            openURL: { _ in }, makePKCE: { PKCE(verifier: "v") })
        return GoogleCalendarService(
            authSession: session, tokenClient: tokenClient,
            eventsClient: GoogleEventsClient(transport: { _ in Data(eventsJSON.utf8) }),
            store: store, context: context, now: now, windowDays: 14)
    }

    func testConnectThenFetchUpserts() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let events = #"{"items":[{"id":"e1","summary":"Standup","status":"confirmed","start":{"dateTime":"\#(ISO8601DateFormatter().string(from: now))"},"end":{"dateTime":"\#(ISO8601DateFormatter().string(from: now.addingTimeInterval(900)))"}}]}"#
        let svc = makeService(store: InMemoryTokenStore(),
                              tokenJSON: #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#,
                              eventsJSON: events, context: ctx, now: { now })
        await svc.connect(credentials: .init(clientId: "c", clientSecret: "s"))
        XCTAssertEqual(svc.state, .connected)
        XCTAssertNotNil(svc.lastSynced)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CalendarEvent>()).map(\.externalId), ["e1"])
    }

    func testRefreshIfNeededRefreshesExpired() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveCredentials(.init(clientId: "c", clientSecret: "s"))
        try store.saveToken(GoogleToken(accessToken: "OLD", refreshToken: "RT", expiresAt: now)) // expired now
        let svc = makeService(store: store,
                              tokenJSON: #"{"access_token":"NEW","expires_in":3600}"#,
                              eventsJSON: #"{"items":[]}"#, context: ctx, now: { now })
        try await svc.refreshIfNeeded()
        XCTAssertEqual(try store.loadToken()?.accessToken, "NEW")
        XCTAssertEqual(try store.loadToken()?.refreshToken, "RT")
    }

    func testDisconnectClearsTokenAndEvents() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveToken(GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(9999)))
        ctx.insert(CalendarEvent(externalId: "e1", title: "X", start: now, end: now))
        try ctx.save()
        let svc = makeService(store: store, tokenJSON: "{}", eventsJSON: #"{"items":[]}"#, context: ctx, now: { now })
        svc.disconnect()
        XCTAssertEqual(svc.state, .disconnected)
        XCTAssertNil(try store.loadToken())
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<CalendarEvent>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GoogleCalendarServiceTests`
Expected: FAIL — `GoogleCalendarService` undefined.

- [ ] **Step 3: Implement `GoogleCalendarService`**

`Sources/MustardKit/Calendar/GoogleCalendarService.swift`:

```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class GoogleCalendarService {
    public enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    public private(set) var state: ConnectionState = .disconnected
    public private(set) var lastSynced: Date?

    private let authSession: GoogleAuthSession
    private let tokenClient: GoogleTokenClient
    private let eventsClient: GoogleEventsClient
    private let store: TokenStore
    private let context: ModelContext
    private let now: () -> Date
    private let windowDays: Int
    private let calendarId = "primary"

    public init(authSession: GoogleAuthSession, tokenClient: GoogleTokenClient,
                eventsClient: GoogleEventsClient, store: TokenStore, context: ModelContext,
                now: @escaping () -> Date = { .now }, windowDays: Int = 14) {
        self.authSession = authSession
        self.tokenClient = tokenClient
        self.eventsClient = eventsClient
        self.store = store
        self.context = context
        self.now = now
        self.windowDays = windowDays
    }

    /// Reflect persisted state at launch.
    public func bootstrap() {
        state = ((try? store.loadToken()) ?? nil) != nil ? .connected : .disconnected
    }

    public func connect(credentials: GoogleCredentials) async {
        state = .connecting
        do {
            _ = try await authSession.connect(credentials: credentials)
            state = .connected
            await fetch()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    public func disconnect() {
        try? store.clearToken()
        purgeEvents()
        lastSynced = nil
        state = .disconnected
    }

    public func refreshIfNeeded() async throws {
        guard let token = try store.loadToken(),
              let creds = try store.loadCredentials() else { throw GoogleAuthError.invalidGrant }
        guard let refresh = token.refreshToken else { return }
        if token.expiresAt.timeIntervalSince(now()) <= 60 {
            let fresh = try await tokenClient.refresh(refreshToken: refresh, credentials: creds)
            try store.saveToken(fresh)
        }
    }

    public func fetch() async {
        do {
            try await refreshIfNeeded()
            guard let token = try store.loadToken() else { state = .disconnected; return }
            let window = CalendarWindow.rolling(from: now(), days: windowDays)
            let events = try await eventsClient.fetch(accessToken: token.accessToken,
                                                      calendarId: calendarId, window: window)
            try upsertEvents(events, into: context, calendarId: calendarId, window: window)
            lastSynced = now()
            state = .connected
        } catch GoogleAuthError.invalidGrant {
            try? store.clearToken()
            state = .disconnected
        } catch {
            state = .failed(Self.message(for: error))   // keep last-synced rows
        }
    }

    private func purgeEvents() {
        let all = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        all.forEach { context.delete($0) }
        try? context.save()
    }

    static func message(for error: Error) -> String {
        switch error as? GoogleAuthError {
        case .denied: return "You declined access."
        case .timeout: return "Timed out waiting for Google."
        case .portBindFailed: return "Couldn't open a local port for sign-in."
        case .invalidGrant: return "Sign-in expired — reconnect."
        case .server(let m): return "Google error: \(m)"
        case .network(let m): return "Network error: \(m)"
        case .missingCode: return "No authorization code received."
        case .none: return error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GoogleCalendarServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all prior tests + the new Calendar tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Calendar/GoogleCalendarService.swift Tests/MustardTests/GoogleCalendarServiceTests.swift
git commit -m "feat(bak-45): GoogleCalendarService orchestrator"
```

---

## Task 8: Settings UI — Google Calendar section

**Files:**
- Modify: `Sources/MustardKit/Views/SourceSettingsView.swift`

> **Read `SourceSettingsView.swift` first** to match its existing section/styling patterns and how it receives services. Use `Theme.Palette`/`Theme.Fonts` — never hardcode colors. This view is verified by **build + Leon's eye**, not unit tests.

- [ ] **Step 1: Add a Google Calendar section**

Add a section bound to a `GoogleCalendarService` (passed via `@Bindable`/`@Environment` consistent with the file's existing pattern). Use local `@State` for the client id/secret fields. Behaviour by `service.state`:

```swift
// Pseudostructure — adapt to SourceSettingsView's real layout/components.
@State private var clientId = ""
@State private var clientSecret = ""

Section("Google Calendar") {
    switch service.state {
    case .disconnected, .failed:
        TextField("OAuth Client ID", text: $clientId)
        SecureField("OAuth Client Secret", text: $clientSecret)
        if case .failed(let msg) = service.state {
            Text(msg).font(Theme.Fonts.caption).foregroundStyle(.red)
        }
        Button("Connect") {
            Task { await service.connect(credentials: .init(clientId: clientId, clientSecret: clientSecret)) }
        }
        .disabled(clientId.isEmpty || clientSecret.isEmpty)
    case .connecting:
        HStack { ProgressView(); Text("Waiting for Google…") }
    case .connected:
        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.Palette.doneGreen)
        if let synced = service.lastSynced {
            Text("Last synced \(synced.formatted(.relative(presentation: .named)))")
                .font(Theme.Fonts.caption)
        }
        Button("Refresh now") { Task { await service.fetch() } }
        Button("Disconnect", role: .destructive) { service.disconnect() }
    }
}
```

On first appearance, prefill `clientId`/`clientSecret` from `store.loadCredentials()` if present (so reconnect after disconnect is one tap). If `SourceSettingsView` doesn't already hold the service, thread it through from `MustardApp` in Task 9 and wire this section then.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/SourceSettingsView.swift
git commit -m "feat(bak-45): Google Calendar connect UI in settings"
```

---

## Task 9: Wire into MustardApp

**Files:**
- Modify: `Sources/Mustard/MustardApp.swift`

> **Read `MustardApp.swift` first** to see how `AgentService`, the `ModelContainer`, and the 60s loop are constructed — mirror those patterns exactly.

- [ ] **Step 1: Construct the service**

Where other services/the container are built, add (using the app's main `ModelContext`):

```swift
let keychain = KeychainTokenStore()
let calendarService = GoogleCalendarService(
    authSession: GoogleAuthSession(
        makeServer: { LoopbackRedirectServer() },
        tokenClient: GoogleTokenClient(),
        store: keychain,
        openURL: { NSWorkspace.shared.open($0) }),
    tokenClient: GoogleTokenClient(),
    eventsClient: GoogleEventsClient(),
    store: keychain,
    context: container.mainContext)
calendarService.bootstrap()
```

Hold it like the other services and inject it into the view tree (so `SourceSettingsView` reaches it) following the file's existing approach (e.g. `.environment(calendarService)` or passed property).

- [ ] **Step 2: Pump from the 60s loop**

In the existing scheduled-sweep loop body, add:

```swift
if calendarService.state == .connected {
    await calendarService.fetch()   // fetch() calls refreshIfNeeded() internally
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles clean.

- [ ] **Step 4: Build the app bundle**

Run: `./build-app.sh`
Expected: `build/Mustard.app` produced.

- [ ] **Step 5: Commit**

```bash
git add Sources/Mustard/MustardApp.swift
git commit -m "feat(bak-45): wire GoogleCalendarService into app + 60s loop"
```

---

## Task 10: Live verification (manual — Leon)

> Unit tests can't cover the real consent screen / socket / Keychain. This is the live smoke test.

- [ ] **Step 1: Full suite + build**

Run: `swift test && swift build`
Expected: green.

- [ ] **Step 2: Live connect**

1. `open build/Mustard.app`
2. Settings → Google Calendar → paste the Desktop client id + secret → **Connect**.
3. Browser opens Google consent → approve → "you can close this tab" page appears.
4. Settings shows **Connected** + a last-synced time.

- [ ] **Step 3: Verify sync**

Real `primary`-calendar meetings (today → +14 days) appear on **Week** and the **notch**. **Refresh now** re-syncs; a cancelled event disappears after refresh.

- [ ] **Step 4: Verify reconnect/disconnect**

**Disconnect** removes synced meetings from Week; reopening Settings keeps the credentials prefilled so **Connect** is one tap.

---

## Self-review notes

- **Spec coverage:** loopback auth (T1,T6), token exchange/refresh (T2), events fetch (T3), Keychain store (T4), upsert + deletion reconcile (T5), `@Observable` service with state/refresh/window/disconnect-purge (T7), Settings UI (T8), 60s-loop wiring (T9), live test (T10). Window=14d, primary-only, readonly scope, disconnect-purge all carried from spec.
- **Type consistency:** `HTTPTransport`, `GoogleCredentials`, `CalendarWindow`, `GoogleAuthError` defined once in T1 and reused; `RedirectServing` (T1) stubbed in T6/T7; `GoogleToken` gains `Codable` in T2 for T4's store; `refresh` carries the existing refresh token forward (T2) which T7's refresh test asserts.
- **Risk:** OAuth/`auth` path → `deep-review` panel before auto-merge (per `.agent-loop/risk.yml`). No irreversible outward action; client secret is user-entered + Keychain-only, never committed.
