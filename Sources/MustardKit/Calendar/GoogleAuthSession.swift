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
