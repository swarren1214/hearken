import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OSLog
import Security

/// Hearken's session with the shared Hearth API (api.hearthapps.com): a Supabase session from
/// Sign in with Apple, kept in the Keychain. Study groups live there.
///
/// Unlike Sated, Hearken never makes an anonymous session: everything else in Hearken works
/// without the API, and study groups need a real account. With no session, calls throw
/// `ClientError.notConnected` and the Study Groups section offers Sign in with Apple.
///
/// Reliability (as in the other Hearth apps):
/// - A token is reused until a minute before it expires.
/// - Only one refresh runs at a time; everyone else waits for it (a refresh token can only be
///   spent once).
/// - Network and server failures never end the session; only Supabase refusing the refresh
///   token does.
///
/// One sign-in for every Hearth app (see `HearthSharedSession` in HearthShared.swift): a session
/// another app signed in with is adopted, one made here is shared, and signing out in any app
/// signs out of all of them.
actor HearthAPI {
    static let shared = HearthAPI()

    nonisolated struct APIError: LocalizedError, Sendable {
        let status: Int
        let code: String
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated enum ClientError: LocalizedError, Sendable {
        /// No Hearth session on this device: sign in with Apple.
        case notConnected
        case invalidResponse
        case service(String)
        /// Supabase refused the request (an expired refresh token, or the sign-in).
        case rejected(String)
        case rateLimited
        case missingAppleToken
        case missingAppleNonce

        var errorDescription: String? {
            switch self {
            case .notConnected: "Sign in with Apple to use study groups."
            case .invalidResponse: "Hearth is having trouble right now. Try again in a moment."
            case .service(let message), .rejected(let message): message
            case .rateLimited: "Too many requests just now. Try again in a minute."
            case .missingAppleToken: "Apple did not provide an identity token. Please try again."
            case .missingAppleNonce: "The Apple sign-in request expired. Please try again."
            }
        }
    }

    nonisolated private struct AuthUser: Codable, Sendable {
        let id: String
        let isAnonymous: Bool?
        let email: String?

        enum CodingKeys: String, CodingKey {
            case id
            case isAnonymous = "is_anonymous"
            case email
        }
    }

    nonisolated private struct AuthSession: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
        let user: AuthUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case user
        }
    }

    nonisolated private struct AuthError: Decodable, Sendable {
        let msg: String?
        let message: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case msg, message
            case errorDescription = "error_description"
        }
    }

    nonisolated private struct ErrorEnvelope: Decodable, Sendable {
        nonisolated struct Detail: Decodable, Sendable {
            let code: String
            let message: String
        }
        let error: Detail
    }

    private static let keychainService = "com.stephenwarren.hearken.hearth-session"
    private static let keychainAccount = "session"
    private static let log = Logger(subsystem: "com.stephenwarren.hearken", category: "hearth-api")

    private let urlSession: URLSession
    private var authSession: AuthSession?
    private var renewal: Task<AuthSession, Error>?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        authSession = Self.loadSession()
    }

    // MARK: State

    /// The Hearth account id (the token's subject), when signed in.
    var userID: String? {
        guard let authSession, authSession.user.isAnonymous != true else { return nil }
        return authSession.user.id
    }

    var isConnected: Bool { userID != nil }

    // MARK: Requests

    /// Sends a request to the Hearth API and returns the body of a 2xx response. A 401 renews the
    /// token once and tries again. Other statuses throw `APIError` with the API's code and message.
    func data(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard !ScreenshotMode.isOn else { throw ClientError.notConnected }
        var result = try await send(method, path, body: body, accessToken: accessToken())
        if result.response.statusCode == 401 {
            result = try await send(method, path, body: body, accessToken: accessToken(renew: true))
        }
        guard (200..<300).contains(result.response.statusCode) else {
            throw Self.apiError(from: result.data, status: result.response.statusCode)
        }
        return result.data
    }

    private func send(_ method: String, _ path: String, body: Data?, accessToken: String) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: AppConfig.apiBaseURL) else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return (data, response)
    }

    /// A valid access token. `renew` forces a refresh, after the API rejected the current one.
    func accessToken(renew: Bool = false) async throws -> String {
        // Another Hearth app may have switched accounts or signed out (one Keychain read).
        if renewal == nil { followSharedSession() }
        if !renew, let authSession, authSession.user.isAnonymous != true,
           authSession.expiresAt > Int(Date().timeIntervalSince1970) + 60 {
            return authSession.accessToken
        }
        if let renewal {
            return try await renewal.value.accessToken
        }
        let rejectedToken = renew ? authSession?.accessToken : nil
        let task = Task { try await self.obtainSession(rejectedToken: rejectedToken) }
        renewal = task
        defer { renewal = nil }
        return try await task.value.accessToken
    }

    /// Refreshes the session. With none, or when Supabase refuses the refresh token, throws
    /// `notConnected`. Network and server failures are thrown as they are.
    private func obtainSession(rejectedToken: String?) async throws -> AuthSession {
        // Another Hearth app may have signed in, out or refreshed since we last looked.
        followSharedSession()
        guard let current = authSession, current.user.isAnonymous != true else { throw ClientError.notConnected }
        if current.accessToken != rejectedToken, current.expiresAt > Int(Date().timeIntervalSince1970) + 60 {
            return current
        }
        do {
            return try await refresh(current.refreshToken)
        } catch ClientError.rejected(let message) {
            // Another Hearth app may have spent this refresh token a moment ago.
            if let shared = HearthAccounts.session(), shared.userID == current.user.id, shared.refreshToken != current.refreshToken {
                let adopted = Self.authSession(from: shared)
                store(adopted)
                if adopted.expiresAt > Int(Date().timeIntervalSince1970) + 60 { return adopted }
                do { return try await refresh(adopted.refreshToken) } catch ClientError.rejected {}
            }
            Self.log.notice("Refresh token rejected (\(message, privacy: .public)); signing out of the Hearth API")
            // Dead in every app (only when Supabase says the refresh token itself is invalid, not
            // for any other 4xx): remove it from the shared sign-in too, if it's still there.
            if Self.isDeadRefreshToken(message) { HearthAccounts.discardSession(ifRefreshToken: authSession?.refreshToken ?? current.refreshToken) }
            Self.markDead(refreshToken: authSession?.refreshToken ?? current.refreshToken)
            forgetSession()
            throw ClientError.notConnected
        }
    }

    private func refresh(_ refreshToken: String) async throws -> AuthSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let refreshed: AuthSession = try await auth(path: "/auth/v1/token?grant_type=refresh_token", body: body)
        store(refreshed)
        // Someone else signed in in another app while this was on its way: never write this
        // account back over theirs (the next look follows them).
        // (No shared session, but it was this account's: signed out elsewhere meanwhile.)
        let sharedNow = HearthAccounts.session()
        let mayShare = sharedNow.map { $0.userID == refreshed.user.id }
            ?? (!HearthAccounts.sessionIsGone || UserDefaults.standard.string(forKey: Self.sharedUserKey) != refreshed.user.id)
        if mayShare { share(refreshed) } else { followSharedSession() }
        return refreshed
    }

    // MARK: Sign in with Apple

    /// Adds a nonce to an Apple sign-in request and returns the raw nonce for `signInWithApple`.
    nonisolated static func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        return nonce
    }

    /// Trades Apple's identity token for a Hearth (Supabase) session and shares it with the other
    /// Hearth apps.
    func signInWithApple(identityToken: Data?, nonce: String?) async throws {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8) else {
            throw ClientError.missingAppleToken
        }
        guard let nonce else { throw ClientError.missingAppleNonce }
        let body = try JSONSerialization.data(withJSONObject: ["provider": "apple", "id_token": token, "nonce": nonce])
        let newSession: AuthSession = try await auth(path: "/auth/v1/token?grant_type=id_token", body: body)
        store(newSession)
        share(newSession)
    }

    private func auth<T: Decodable>(path: String, body: Data) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.supabaseURL) else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(AppConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch response.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClientError.invalidResponse }
        case 429:
            throw ClientError.rateLimited
        case 400..<500:
            throw ClientError.rejected(Self.authMessage(from: data, status: response.statusCode))
        default:
            throw ClientError.service(Self.authMessage(from: data, status: response.statusCode))
        }
    }

    // MARK: One sign-in for every Hearth app

    nonisolated private static let sharedUserKey = "hearth.api.sharedSessionUserID"
    nonisolated private static let deadTokenKey = "hearth.api.deadRefreshToken"

    /// Applies the shared sign-in rules: adopts a session another Hearth app signed in with,
    /// shares one made here, and forgets ours when the shared one was signed out elsewhere.
    /// Returns whether being connected changed.
    @discardableResult
    func followSharedSession() -> Bool {
        guard !ScreenshotMode.isOn else { return false }
        let before = isConnected
        let defaults = UserDefaults.standard
        if let shared = HearthAccounts.session() {
            if Self.isDead(refreshToken: shared.refreshToken) {
                if let current = authSession, isConnected { share(current) }
            } else if let current = authSession, isConnected, current.user.id == shared.userID {
                if defaults.string(forKey: Self.sharedUserKey) != shared.userID { defaults.set(shared.userID, forKey: Self.sharedUserKey) }
                // Same person: keep whichever token lasts longer.
                if shared.refreshToken != current.refreshToken {
                    if Int(shared.expiresAt) > current.expiresAt { store(Self.authSession(from: shared)) }
                    else if current.expiresAt > Int(shared.expiresAt) { share(current) }
                }
            } else {
                store(Self.authSession(from: shared))
                defaults.set(shared.userID, forKey: Self.sharedUserKey)
            }
        } else if HearthAccounts.sessionIsGone, let current = authSession, isConnected {
            // (Only when it's really gone: a sign-in the Keychain can't read right now isn't a
            // sign-out.)
            if defaults.string(forKey: Self.sharedUserKey) == current.user.id {
                // Shared once, now gone: signed out in another Hearth app.
                forgetSession()
            } else {
                share(current)
            }
        }
        return before != isConnected
    }

    /// Forgets this app's session (signing out of Hearken). Signing out everywhere also clears
    /// the shared one, through `HearthAccounts.signOutEverywhere()`.
    func signOut() {
        // Don't adopt the shared session again on the next look: this person signed out here.
        if let shared = HearthAccounts.session() { Self.markDead(refreshToken: shared.refreshToken) }
        forgetSession()
    }

    private func share(_ session: AuthSession) {
        guard !ScreenshotMode.isOn, session.user.isAnonymous != true else { return }
        HearthAccounts.saveSession(HearthSharedSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Double(session.expiresAt),
            userID: session.user.id,
            email: session.user.email,
            updatedBy: .hearken
        ))
        UserDefaults.standard.set(session.user.id, forKey: Self.sharedUserKey)
    }

    private func forgetSession() {
        Self.deleteStoredSession()
        authSession = nil
        UserDefaults.standard.removeObject(forKey: Self.sharedUserKey)
    }

    private nonisolated static func authSession(from shared: HearthSharedSession) -> AuthSession {
        AuthSession(accessToken: shared.accessToken, refreshToken: shared.refreshToken, expiresAt: Int(shared.expiresAt),
                    user: AuthUser(id: shared.userID, isAnonymous: false, email: shared.email))
    }

    private nonisolated static func tokenHash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Supabase's answer when the refresh token itself is no good ("Invalid Refresh Token: …"),
    /// as opposed to any other rejected request.
    private nonisolated static func isDeadRefreshToken(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("refresh token") || message.localizedCaseInsensitiveContains("invalid_grant")
    }

    private nonisolated static func markDead(refreshToken: String) {
        UserDefaults.standard.set(tokenHash(refreshToken), forKey: deadTokenKey)
    }

    private nonisolated static func isDead(refreshToken: String) -> Bool {
        UserDefaults.standard.string(forKey: deadTokenKey) == tokenHash(refreshToken)
    }

    // MARK: Keychain

    private func store(_ session: AuthSession) {
        authSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Self.log.error("Couldn't save the Hearth session to the Keychain (\(status))")
        }
    }

    private nonisolated static func loadSession() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private nonisolated static func deleteStoredSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Errors

    private nonisolated static func authMessage(from data: Data, status: Int) -> String {
        let detail = try? JSONDecoder().decode(AuthError.self, from: data)
        return detail?.message ?? detail?.msg ?? detail?.errorDescription ?? "Hearth couldn’t sign you in right now. Try again in a moment."
    }

    private nonisolated static func apiError(from data: Data, status: Int) -> APIError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return APIError(status: status, code: envelope.error.code, message: envelope.error.message)
        }
        return APIError(status: status, code: "HTTP_\(status)", message: "The Hearth service returned HTTP \(status).")
    }
}

/// Whether Hearken has a Hearth account session, for the screens that need one. Follows sign-ins
/// and sign-outs in the other Hearth apps while Hearken is open.
@MainActor
@Observable
final class HearthConnection {
    static let shared = HearthConnection()

    private(set) var isConnected = false
    /// True after the first check, so screens don't flash "Sign in" while it's unknown.
    private(set) var hasChecked = false
    private(set) var isConnecting = false
    var errorMessage: String?

    @ObservationIgnored private var observer: NSObjectProtocol?
    /// The Hearth account the study groups on screen belong to.
    @ObservationIgnored private var connectedUserID: String?

    /// Re-reads the session, following the other Hearth apps.
    func update() async {
        if ScreenshotMode.isOn {
            isConnected = true
            hasChecked = true
            return
        }
        if observer == nil {
            Hearth.startObservingChanges()
            observer = NotificationCenter.default.addObserver(forName: Hearth.didChange, object: nil, queue: .main) { _ in
                Task { @MainActor in await HearthConnection.shared.update() }
            }
        }
        let api = HearthAPI.shared
        await api.followSharedSession()
        let userID = await api.userID
        let connected = userID != nil
        let changed = connected != isConnected
        // Another Hearth app switched accounts: the groups (and push token) were the old one's.
        let switched = connected && isConnected && connectedUserID != nil && userID != connectedUserID
        isConnected = connected
        connectedUserID = userID
        hasChecked = true
        if switched {
            GroupStore.shared.forget()
            await GroupStore.shared.refresh()
            await GroupStore.shared.didConnect()
        } else if changed {
            await GroupStore.shared.refresh()
        }
    }

    /// The second half of a Sign in with Apple button that asked for a nonce
    /// (`HearthAPI.prepareAppleRequest`): signs in to the Hearth API.
    func connect(credential: ASAuthorizationAppleIDCredential, nonce: String?) async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await HearthAPI.shared.signInWithApple(identityToken: credential.identityToken, nonce: nonce)
            errorMessage = nil
        } catch {
            Logger(subsystem: "com.stephenwarren.hearken", category: "hearth-api")
                .error("Hearth sign-in failed: \(String(describing: error), privacy: .public)")
            errorMessage = FriendlyError.signIn(error)
        }
        await update()
        await GroupStore.shared.refresh()
        await GroupStore.shared.didConnect()
    }

    func signOut() async {
        await HearthAPI.shared.signOut()
        await update()
    }
}
