import Foundation

/// HTTP for the OAuth token endpoint. Body builders are pure; the network is injected.
public struct GoogleTokenClient {
    let transport: HTTPTransport

    public init(transport: @escaping HTTPTransport = GoogleTokenClient.defaultTransport) {
        self.transport = transport
    }

    public static let defaultTransport: HTTPTransport = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
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
        return try await parseToken(from: try await post(body))
    }

    public func refresh(refreshToken: String, credentials: GoogleCredentials) async throws -> GoogleToken {
        let body = Self.refreshBody(refreshToken: refreshToken, clientId: credentials.clientId,
                                    clientSecret: credentials.clientSecret)
        let token = try await parseToken(from: try await post(body))
        // Refresh responses omit refresh_token — carry the existing one forward.
        if token.refreshToken == nil {
            return GoogleToken(accessToken: token.accessToken, refreshToken: refreshToken, expiresAt: token.expiresAt)
        }
        return token
    }

    private func parseToken(from response: (data: Data, status: Int)) throws -> GoogleToken {
        guard (200..<300).contains(response.status) else {
            throw Self.error(from: response.data, status: response.status)
        }
        guard let token = GoogleOAuth.parseTokenResponse(response.data) else {
            throw GoogleAuthError.server("unexpected token response")
        }
        return token
    }

    private func post(_ body: String) async throws -> (data: Data, status: Int) {
        var req = URLRequest(url: URL(string: GoogleOAuth.tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        let (data, status) = try await transport(req)
        return (data, status)
    }

    static func error(from data: Data, status: Int) -> GoogleAuthError {
        struct Err: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Err.self, from: data))?.error
        if code == "invalid_grant" { return .invalidGrant }
        return .server(code ?? "token status \(status)")
    }

    static func formEncode(_ pairs: [(String, String)]) -> String {
        var c = URLComponents()
        c.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.percentEncodedQuery ?? ""
    }
}
