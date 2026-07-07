import XCTest
import SwiftData
@testable import MustardKit

/// Thread-safe call counter for the token-refresh-race test below.
private actor RefreshCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
final class GoogleCalendarServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: CalendarEvent.self, configurations: config))
    }

    private func makeService(store: TokenStore, tokenJSON: String, tokenStatus: Int = 200,
                             eventsJSON: String, eventsStatus: Int = 200,
                             context: ModelContext, now: @escaping () -> Date) -> GoogleCalendarService {
        let tokenClient = GoogleTokenClient(transport: { _ in (Data(tokenJSON.utf8), tokenStatus) })
        let session = GoogleAuthSession(
            makeServer: { StubRedirectServer() }, tokenClient: tokenClient, store: store,
            openURL: { _ in }, makePKCE: { PKCE(verifier: "v") }, makeState: { "s" })
        return GoogleCalendarService(
            authSession: session, tokenClient: tokenClient,
            eventsClient: GoogleEventsClient(transport: { _ in (Data(eventsJSON.utf8), eventsStatus) }),
            store: store, context: context, now: now, windowDays: 14)
    }

    func testConnectThenFetchUpserts() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let f = ISO8601DateFormatter()
        let startStr = f.string(from: now.addingTimeInterval(3600))
        let endStr = f.string(from: now.addingTimeInterval(4500))
        let events = "{\"items\":[{\"id\":\"e1\",\"summary\":\"Standup\",\"status\":\"confirmed\",\"start\":{\"dateTime\":\"\(startStr)\"},\"end\":{\"dateTime\":\"\(endStr)\"}}]}"
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

    func testRefreshIfNeededRefreshesNearExpiry() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveCredentials(.init(clientId: "c", clientSecret: "s"))
        // Within the 60s skew → must refresh.
        try store.saveToken(GoogleToken(accessToken: "OLD", refreshToken: "RT", expiresAt: now.addingTimeInterval(30)))
        let svc = makeService(store: store,
                              tokenJSON: #"{"access_token":"NEW","expires_in":3600}"#,
                              eventsJSON: #"{"items":[]}"#, context: ctx, now: { now })
        try await svc.refreshIfNeeded()
        XCTAssertEqual(try store.loadToken()?.accessToken, "NEW")
    }

    func testRefreshIfNeededSkipsWhenValid() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveCredentials(.init(clientId: "c", clientSecret: "s"))
        // Far from expiry → must NOT refresh (token stays OLD even though transport would return NEW).
        try store.saveToken(GoogleToken(accessToken: "OLD", refreshToken: "RT", expiresAt: now.addingTimeInterval(3600)))
        let svc = makeService(store: store,
                              tokenJSON: #"{"access_token":"NEW","expires_in":3600}"#,
                              eventsJSON: #"{"items":[]}"#, context: ctx, now: { now })
        try await svc.refreshIfNeeded()
        XCTAssertEqual(try store.loadToken()?.accessToken, "OLD")
    }

    func testFetchServerErrorKeepsEventsAndStaysConnectedFailure() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveCredentials(.init(clientId: "c", clientSecret: "s"))
        try store.saveToken(GoogleToken(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(3600)))
        ctx.insert(CalendarEvent(externalId: "keep", title: "X", start: now, end: now))
        try ctx.save()
        // Events endpoint 503 → must NOT wipe the synced rows.
        let svc = makeService(store: store, tokenJSON: "{}",
                              eventsJSON: "oops", eventsStatus: 503, context: ctx, now: { now })
        await svc.fetch()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CalendarEvent>()).map(\.externalId), ["keep"])
        guard case .failed = svc.state else { return XCTFail("expected .failed, got \(svc.state)") }
    }

    /// Two concurrent callers both see an expired token and both call `refreshIfNeeded()`
    /// (e.g. two overlapping `fetch()`s). Without serialization each would hit the
    /// network and the loser's write could clobber the winner's fresh token. Assert
    /// the transport is only ever hit once.
    func testConcurrentRefreshIfNeededPerformsExactlyOneNetworkRefresh() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let store = InMemoryTokenStore()
        try store.saveCredentials(.init(clientId: "c", clientSecret: "s"))
        try store.saveToken(GoogleToken(accessToken: "OLD", refreshToken: "RT", expiresAt: now)) // expired now

        let counter = RefreshCallCounter()
        let tokenClient = GoogleTokenClient(transport: { _ in
            await counter.increment()
            // Hold the "network call" open briefly so a second, unserialized caller
            // would have time to start its own refresh before the first completes.
            try await Task.sleep(nanoseconds: 20_000_000)
            return (Data(#"{"access_token":"NEW","expires_in":3600}"#.utf8), 200)
        })
        let session = GoogleAuthSession(
            makeServer: { StubRedirectServer() }, tokenClient: tokenClient, store: store,
            openURL: { _ in }, makePKCE: { PKCE(verifier: "v") }, makeState: { "s" })
        let svc = GoogleCalendarService(
            authSession: session, tokenClient: tokenClient,
            eventsClient: GoogleEventsClient(transport: { _ in (Data(#"{"items":[]}"#.utf8), 200) }),
            store: store, context: ctx, now: { now }, windowDays: 14)

        async let first: Void = svc.refreshIfNeeded()
        async let second: Void = svc.refreshIfNeeded()
        _ = try await (first, second)

        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try store.loadToken()?.accessToken, "NEW")
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
