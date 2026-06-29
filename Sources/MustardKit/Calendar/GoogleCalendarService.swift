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

    /// Persisted credentials, if any — lets the Settings UI prefill for one-tap reconnect.
    public func savedCredentials() -> GoogleCredentials? {
        (try? store.loadCredentials()) ?? nil
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
