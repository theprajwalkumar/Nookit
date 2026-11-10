import SwiftUI
import Foundation
import AppKit
import CryptoKit
import Network
import Security

// MARK: - Stored credentials

struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String
    var email: String?
    var name: String?
}

/// Storage for the OAuth token blob.
///
/// Why not the Keychain? Nookit is ad-hoc signed and rebuilt often, so its code
/// signature changes on every build. macOS ties legacy keychain item ACLs to
/// that signature, which means reading a previously stored item pops a blocking
/// SecurityAgent password prompt after each rebuild. Because that read used to
/// happen inside `GoogleAuthService.init()` on the main thread, the prompt could
/// hang app launch forever. The modern data-protection keychain refuses ad-hoc
/// apps outright (`errSecMissingEntitlement`), so neither Keychain flavour is a
/// safe fit here.
///
/// Tokens therefore live in a `0600` file inside Application Support. Reads are
/// a tiny local file access that never prompts and never blocks the UI, while
/// the file stays private to the current user.
enum TokenStore {
    private static var fileURL: URL { AppPaths.supportFile("google-tokens.json") }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func save(_ data: Data) {
        let url = fileURL
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - PKCE helpers

enum GooglePKCE {
    static func verifier(length: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback redirect server

/// Accepts exactly one browser redirect on `127.0.0.1` and hands the query
/// back to the OAuth flow. Google desktop clients allow any loopback port, so
/// the port is chosen at runtime and needs no pre-registration.
final class LoopbackOAuthServer {
    private let queue = DispatchQueue(label: "app.nookit.oauth.loopback")
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private(set) var port: UInt16 = 0
    private var finished = false

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let value = listener.port?.rawValue ?? 0
                    self.port = value
                    self.resumeReady(.success(value))
                case .failed(let error):
                    self.resumeReady(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
    }

    func waitForCallback(timeout: TimeInterval = 180) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask { try await self.awaitCallback() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ToolError.message("Google sign-in timed out. Try connecting again.")
            }
            guard let first = try await group.next() else {
                throw ToolError.message("Google sign-in stopped before it finished.")
            }
            group.cancelAll()
            return first
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.finish(.failure(ToolError.message("Google sign-in was cancelled.")))
        }
    }

    private func awaitCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ToolError.message("Google sign-in stopped."))
                    return
                }
                if let pending = self.pending {
                    self.pending = nil
                    continuation.resume(with: pending)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    private func resumeReady(_ result: Result<UInt16, Error>) {
        queue.async { [weak self] in
            guard let self, let continuation = self.readyContinuation else { return }
            self.readyContinuation = nil
            continuation.resume(with: result)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                self.respond(connection, status: "400 Bad Request", body: "Nookit could not read the Google response.")
                return
            }

            let pieces = firstLine.components(separatedBy: " ")
            guard pieces.count >= 2 else {
                self.respond(connection, status: "400 Bad Request", body: "Nookit could not read the Google response.")
                return
            }

            let path = pieces[1]
            guard path != "/favicon.ico" else {
                connection.cancel()
                return
            }

            guard let components = URLComponents(string: "http://127.0.0.1\(path)") else {
                self.respond(connection, status: "400 Bad Request", body: "Malformed sign-in response.")
                return
            }

            var values: [String: String] = [:]
            for item in components.queryItems ?? [] {
                values[item.name] = item.value ?? ""
            }

            if let error = values["error"] {
                let description = values["error_description"]?.replacingOccurrences(of: "+", with: " ") ?? error
                self.respond(connection, status: "200 OK", body: "Google sign-in was cancelled. You can close this tab.")
                self.finish(.failure(ToolError.message(description)))
                return
            }

            guard values["code"] != nil else {
                self.respond(connection, status: "400 Bad Request", body: "Google did not return an authorization code.")
                self.finish(.failure(ToolError.message("Google did not return an authorization code.")))
                return
            }

            self.respond(connection, status: "200 OK", body: "Nookit is connected to Google. You can close this tab and return to the app.")
            self.finish(.success(values))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Nookit</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0A0B0E;color:#F6F3EC;display:grid;place-items:center;height:100vh;margin:0}
        .card{max-width:420px;padding:32px;border:1px solid rgba(255,255,255,.12);border-radius:18px;background:#171A21;text-align:center}
        h1{font-size:18px;margin:0 0 8px}p{font-size:13px;line-height:1.5;color:#9CA0AA;margin:0}</style></head>
        <body><div class="card"><h1>Nookit</h1><p>\(body)</p></div></body></html>
        """
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.listener?.cancel()
            self.listener = nil

            if let continuation = self.callbackContinuation {
                self.callbackContinuation = nil
                continuation.resume(with: result)
            } else {
                self.pending = result
            }
        }
    }
}

// MARK: - OAuth service

/// Handles Google's installed-app OAuth flow with PKCE and a loopback redirect.
/// Once connected, `authorizedRequest` transparently refreshes the access token.
@MainActor
final class GoogleAuthService: ObservableObject {
    static let shared = GoogleAuthService()

    @Published var clientID: String {
        didSet { defaults.set(clientID, forKey: Keys.clientID) }
    }
    @Published var clientSecret: String {
        didSet { defaults.set(clientSecret, forKey: Keys.clientSecret) }
    }

    @Published private(set) var tokens: GoogleTokens?
    @Published private(set) var connecting = false
    @Published private(set) var needsReauth = false
    @Published var error: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let clientID = "NookitGoogleClientID"
        static let clientSecret = "NookitGoogleClientSecret"
    }

    /// Everything Apps can do on the user's behalf. `drive.file` keeps file
    /// access limited to documents Nookit creates.
    static let scopes: [String] = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/documents",
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/presentations",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/drive.file"
    ]

    static let scopeText = scopes.joined(separator: " ")

    private init() {
        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        clientSecret = defaults.string(forKey: Keys.clientSecret) ?? ""
        loadTokens()
    }

    var isConnected: Bool { tokens != nil && !needsReauth }
    var hasClientID: Bool { !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var accountEmail: String? { tokens?.email }
    var accountName: String? { tokens?.name }

    var statusText: String {
        if connecting { return "Waiting for Google…" }
        if isConnected { return tokens?.email ?? "Google connected" }
        if needsReauth { return "Reconnect Google" }
        return "Google not connected"
    }

    // MARK: Configuration

    func saveConfiguration(clientID: String, clientSecret: String) {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmedID != self.clientID
        self.clientID = trimmedID
        self.clientSecret = trimmedSecret
        if changed {
            disconnect(clearError: false)
        }
        error = nil
    }

    // MARK: Connect

    func connect() async {
        guard !connecting else { return }
        error = nil
        needsReauth = false

        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            error = "Add a Google OAuth client ID first."
            return
        }

        connecting = true
        let server = LoopbackOAuthServer()
        defer { connecting = false }

        do {
            let port = try await server.start()
            let redirectURI = "http://127.0.0.1:\(port)"
            let verifier = GooglePKCE.verifier()
            let challenge = GooglePKCE.challenge(for: verifier)
            let state = GooglePKCE.verifier(length: 24)

            guard let authURL = Self.authorizationURL(
                clientID: trimmedID,
                redirectURI: redirectURI,
                state: state,
                challenge: challenge
            ) else {
                throw ToolError.message("The Google sign-in URL could not be built.")
            }

            guard NSWorkspace.shared.open(authURL) else {
                throw ToolError.message("macOS blocked the browser. Open the Google sign-in URL manually and try again.")
            }

            let callback = try await server.waitForCallback()
            server.stop()

            guard callback["state"] == state else {
                throw ToolError.message("Google sign-in failed its security check. Try again.")
            }
            guard let code = callback["code"], !code.isEmpty else {
                throw ToolError.message("Google did not return an authorization code.")
            }

            let response = try await Self.exchangeCode(
                code: code,
                verifier: verifier,
                redirectURI: redirectURI,
                clientID: trimmedID,
                clientSecret: clientSecret
            )

            var profile = (email: response.email, name: response.name)
            if profile.email == nil, let idToken = response.idToken {
                profile = Self.profile(fromIDToken: idToken)
            }

            let stored = GoogleTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? tokens?.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(max(30, response.expiresIn))),
                scope: response.scope ?? Self.scopeText,
                email: profile.email ?? tokens?.email,
                name: profile.name ?? tokens?.name
            )
            persist(stored)
            tokens = stored
            needsReauth = false
        } catch {
            server.stop()
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("cancelled") {
                self.error = nil
            } else {
                self.error = message
            }
        }
    }

    func disconnect(clearError: Bool = true) {
        TokenStore.clear()
        tokens = nil
        needsReauth = false
        if clearError { error = nil }
    }

    // MARK: Tokens

    /// Returns a usable access token, refreshing when it is close to expiring.
    func validAccessToken() async throws -> String {
        guard var stored = tokens else {
            throw ToolError.message("Connect your Google account first.")
        }
        if stored.expiresAt.timeIntervalSinceNow > 90 {
            return stored.accessToken
        }
        guard let refresh = stored.refreshToken, !refresh.isEmpty else {
            needsReauth = true
            throw ToolError.message("Google access expired. Reconnect your account.")
        }

        let response = try await Self.refresh(
            refreshToken: refresh,
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret
        )
        stored.accessToken = response.accessToken
        stored.expiresAt = Date().addingTimeInterval(TimeInterval(max(30, response.expiresIn)))
        stored.scope = response.scope ?? stored.scope
        if let rotated = response.refreshToken, !rotated.isEmpty {
            stored.refreshToken = rotated
        }
        persist(stored)
        tokens = stored
        return stored.accessToken
    }

    func authorizedRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        let token = try await validAccessToken()
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authorized)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("Google returned no HTTP response.")
        }

        if http.statusCode == 401 {
            // Force one refresh, then retry the original request.
            if var stored = tokens {
                stored.expiresAt = .distantPast
                persist(stored)
                tokens = stored
            }
            let retryToken = try await validAccessToken()
            authorized.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: authorized)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw ToolError.message("Google returned no HTTP response.")
            }
            return (retryData, retryHTTP)
        }

        return (data, http)
    }

    // MARK: Pure builders (testable)

    static func authorizationURL(clientID: String, redirectURI: String, state: String, challenge: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopeText),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let scope: String?
        let idToken: String?
        let email: String?
        let name: String?
    }

    static func exchangeCode(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String,
        clientSecret: String
    ) async throws -> TokenResponse {
        var items: [(String, String)] = [
            ("code", code),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier)
        ]
        if !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("client_secret", clientSecret))
        }

        let (data, http) = try await tokenRequest(items: items)
        guard (200..<300).contains(http.statusCode) else {
            throw ToolError.message(Self.tokenError(data: data, status: http.statusCode))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ToolError.message("Google returned an unreadable token response.")
        }

        var email: String?
        var name: String?
        if let idToken = json["id_token"] as? String {
            let profile = profile(fromIDToken: idToken)
            email = profile.email
            name = profile.name
        }

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int ?? 3_600,
            scope: json["scope"] as? String,
            idToken: json["id_token"] as? String,
            email: email,
            name: name
        )
    }

    static func refresh(refreshToken: String, clientID: String, clientSecret: String) async throws -> TokenResponse {
        var items: [(String, String)] = [
            ("refresh_token", refreshToken),
            ("client_id", clientID),
            ("grant_type", "refresh_token")
        ]
        if !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("client_secret", clientSecret))
        }

        let (data, http) = try await tokenRequest(items: items)
        guard (200..<300).contains(http.statusCode) else {
            throw ToolError.message(Self.tokenError(data: data, status: http.statusCode))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ToolError.message("Google returned an unreadable refresh response.")
        }

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int ?? 3_600,
            scope: json["scope"] as? String,
            idToken: json["id_token"] as? String,
            email: nil,
            name: nil
        )
    }

    static func profile(fromIDToken token: String) -> (email: String?, name: String?) {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (json["email"] as? String, json["name"] as? String)
    }

    static func tokenRequestBody(_ items: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func tokenRequest(items: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = tokenRequestBody(items)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("Google returned no HTTP response.")
        }
        return (data, http)
    }

    private static func tokenError(data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["error_description"] as? String, !message.isEmpty {
                return message
            }
            if let error = json["error"] as? String {
                switch error {
                case "invalid_grant": return "Google rejected the sign-in. Reconnect your account."
                case "invalid_client": return "Google did not recognise this OAuth client. Check the client ID and secret."
                default: return "Google sign-in failed (\(error))."
                }
            }
        }
        return "Google sign-in failed (HTTP \(status))."
    }

    // MARK: Persistence

    private func persist(_ tokens: GoogleTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        TokenStore.save(data)
    }

    /// Reads the token file. This is a tiny local file access with no keychain
    /// prompt, so it is safe to run during `init()` without stalling launch.
    private func loadTokens() {
        guard let data = TokenStore.load(),
              let stored = try? JSONDecoder().decode(GoogleTokens.self, from: data) else {
            return
        }
        tokens = stored
        if stored.refreshToken == nil && stored.expiresAt < Date() {
            needsReauth = true
        }
    }
}
