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
