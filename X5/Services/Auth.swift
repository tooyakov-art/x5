import Foundation
import AuthenticationServices

@MainActor
final class Auth: ObservableObject {
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userId: String?

    let supabase = SupabaseClient()

    var accessToken: String? { supabase.accessToken }

    /// Token keys live in the Keychain (encrypted at rest, excluded from iCloud backups).
    /// User profile keys (id, email) stay in UserDefaults — non-sensitive identifiers.
    private let tokenKey = "x5.session.access_token"
    private let refreshKey = "x5.session.refresh_token"
    private let userIdKey = "x5.session.user_id"
    private let emailKey = "x5.session.email"
    private let migrationFlag = "x5.session.keychain_migrated_v1"

    init() {
        migrateLegacyTokensToKeychain()

        // When SupabaseClient auto-refreshes the JWT (on a 401), persist the new tokens.
        supabase.onSessionRefreshed = { [weak self] session in
            guard let self else { return }
            Keychain.set(session.accessToken, for: self.tokenKey)
            if let refresh = session.refreshToken {
                Keychain.set(refresh, for: self.refreshKey)
            }
        }
        loadStoredSession()
    }

    /// One-time migration: tokens used to live in UserDefaults (plaintext, included
    /// in iTunes/iCloud backups). Move them to the Keychain on first run.
    private func migrateLegacyTokensToKeychain() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlag) else { return }
        if let access = defaults.string(forKey: tokenKey) {
            Keychain.set(access, for: tokenKey)
            defaults.removeObject(forKey: tokenKey)
        }
        if let refresh = defaults.string(forKey: refreshKey) {
            Keychain.set(refresh, for: refreshKey)
            defaults.removeObject(forKey: refreshKey)
        }
        defaults.set(true, forKey: migrationFlag)
    }

    func signInWithApple(authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.invalidCredential
        }

        let session = try await supabase.signInWithApple(identityToken: identityToken)
        store(session: session)
    }

    /// Google Sign-In via the native iOS SDK (GIDSignIn). Trades the Google idToken
    /// for a Supabase session — same path as Apple Sign-In, no Safari involved.
    /// Bypasses Google's "unverified app" block that affected ASWebAuthenticationSession.
    func signInWithGoogle() async throws {
        let idToken = try await OAuthSession.shared.googleIdToken()
        let session = try await supabase.signInWithGoogle(idToken: idToken)
        store(session: session)
    }

    func signInWithEmail(_ email: String, password: String) async throws {
        let session = try await supabase.signInWithEmailPassword(email: email, password: password)
        store(session: session)
    }

    func signUpWithEmail(_ email: String, password: String) async throws {
        let session = try await supabase.signUpWithEmailPassword(email: email, password: password)
        store(session: session)
    }

    func signOut() async {
        clearStorage()
        supabase.accessToken = nil
        supabase.refreshToken = nil
        isAuthenticated = false
        userEmail = nil
        userId = nil
        // Drop private chat media + in-memory layer so a different user signing
        // in on this device can't see leftovers from the previous session.
        await ImageCache.shared.clearForSignOut()
        // Per-chat local UI state (archived / muted / hidden) is per-account.
        ChatsLocalState.reset()
        // Wipe the per-chat message cache on disk — without this a different
        // user signing in on the same device could read the previous user's
        // message history (and signed media URLs) from `Caches/x5-chats/`.
        ChatsService.clearDiskCache()
        NotificationCenter.default.post(name: .x5UserDidSignOut, object: nil)
    }

    func deleteAccount() async throws {
        try await supabase.deleteOwnAccount()
        await signOut()
    }

    // MARK: - Persistence

    private func loadStoredSession() {
        let defaults = UserDefaults.standard
        guard let token = Keychain.string(for: tokenKey),
              let uid = defaults.string(forKey: userIdKey)
        else {
            return
        }
        supabase.accessToken = token
        supabase.refreshToken = Keychain.string(for: refreshKey)
        userId = uid
        userEmail = defaults.string(forKey: emailKey)
        isAuthenticated = true
    }

    private func store(session: SupabaseSession) {
        Keychain.set(session.accessToken, for: tokenKey)
        Keychain.set(session.refreshToken, for: refreshKey)

        let defaults = UserDefaults.standard
        defaults.set(session.user.id, forKey: userIdKey)
        defaults.set(session.user.email, forKey: emailKey)

        supabase.accessToken = session.accessToken
        supabase.refreshToken = session.refreshToken
        userId = session.user.id
        userEmail = session.user.email
        isAuthenticated = true
    }

    private func clearStorage() {
        Keychain.delete(tokenKey)
        Keychain.delete(refreshKey)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: emailKey)
    }
}

enum AuthError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Apple did not return a valid identity token."
        }
    }
}
