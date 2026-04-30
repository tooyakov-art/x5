import Foundation
import AuthenticationServices

@MainActor
final class Auth: ObservableObject {
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userId: String?

    let supabase = SupabaseClient()

    var accessToken: String? { supabase.accessToken }

    private let tokenKey = "x5.session.access_token"
    private let refreshKey = "x5.session.refresh_token"
    private let userIdKey = "x5.session.user_id"
    private let emailKey = "x5.session.email"

    init() {
        // When SupabaseClient auto-refreshes the JWT (on a 401), persist the new tokens.
        supabase.onSessionRefreshed = { [weak self] session in
            guard let self else { return }
            let defaults = UserDefaults.standard
            defaults.set(session.accessToken, forKey: self.tokenKey)
            if let refresh = session.refreshToken {
                defaults.set(refresh, forKey: self.refreshKey)
            }
        }
        loadStoredSession()
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

    func signOut() async {
        clearStorage()
        supabase.accessToken = nil
        supabase.refreshToken = nil
        isAuthenticated = false
        userEmail = nil
        userId = nil
        NotificationCenter.default.post(name: .x5UserDidSignOut, object: nil)
    }

    func deleteAccount() async throws {
        try await supabase.deleteOwnAccount()
        await signOut()
    }

    // MARK: - Persistence

    private func loadStoredSession() {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: tokenKey),
              let uid = defaults.string(forKey: userIdKey)
        else {
            return
        }
        supabase.accessToken = token
        supabase.refreshToken = defaults.string(forKey: refreshKey)
        userId = uid
        userEmail = defaults.string(forKey: emailKey)
        isAuthenticated = true
    }

    private func store(session: SupabaseSession) {
        let defaults = UserDefaults.standard
        defaults.set(session.accessToken, forKey: tokenKey)
        defaults.set(session.refreshToken, forKey: refreshKey)
        defaults.set(session.user.id, forKey: userIdKey)
        defaults.set(session.user.email, forKey: emailKey)

        supabase.accessToken = session.accessToken
        supabase.refreshToken = session.refreshToken
        userId = session.user.id
        userEmail = session.user.email
        isAuthenticated = true
    }

    private func clearStorage() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: refreshKey)
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
