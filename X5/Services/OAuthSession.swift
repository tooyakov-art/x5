import Foundation
import AuthenticationServices

/// ASWebAuthenticationSession runner for Supabase OAuth providers (Google, etc.).
/// Opens Supabase /authorize URL, captures the x5://callback redirect with tokens.
@MainActor
final class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthSession()

    private let supabaseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    static let redirectScheme = "x5"
    static let redirectURL = "x5://callback"

    /// Returns (accessToken, refreshToken) on success.
    func startGoogleSignIn() async throws -> (access: String, refresh: String?) {
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.redirectURL)
        ]
        guard let authURL = components.url else { throw OAuthError.badURL }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            func resumeOnce(_ block: () -> Void) {
                guard !resumed else { return }
                resumed = true
                block()
            }

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.redirectScheme
            ) { callbackURL, error in
                if let error = error as NSError? {
                    // Cancellation: don't pollute UI with errors
                    if error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        resumeOnce { continuation.resume(throwing: OAuthError.cancelled) }
                    } else {
                        resumeOnce { continuation.resume(throwing: error) }
                    }
                    return
                }
                guard let callbackURL else {
                    resumeOnce { continuation.resume(throwing: OAuthError.cancelled) }
                    return
                }
                // Supabase puts tokens in fragment (#access_token=...) on success,
                // or query (?error=...&error_description=...) on failure.
                let raw = callbackURL.absoluteString
                var parts: [String: String] = [:]
                for piece in [raw.components(separatedBy: "#").last,
                              raw.components(separatedBy: "?").last] {
                    guard let piece else { continue }
                    for pair in piece.components(separatedBy: "&") {
                        let kv = pair.components(separatedBy: "=")
                        if kv.count == 2 {
                            parts[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                        }
                    }
                }
                if let access = parts["access_token"] {
                    resumeOnce { continuation.resume(returning: (access, parts["refresh_token"])) }
                } else if let err = parts["error_description"] ?? parts["error"] {
                    resumeOnce {
                        continuation.resume(throwing: NSError(
                            domain: "OAuth", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: err.replacingOccurrences(of: "+", with: " ")]
                        ))
                    }
                } else {
                    resumeOnce { continuation.resume(throwing: OAuthError.noToken) }
                }
            }
            session.presentationContextProvider = self
            // ephemeral=true → fresh session every time, avoids Google "browser not supported"
            // when Safari already has a stale Google session that conflicts with the OAuth flow.
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    enum OAuthError: LocalizedError {
        case badURL, cancelled, noToken
        var errorDescription: String? {
            switch self {
            case .badURL: return "Bad authorize URL"
            case .cancelled: return "Sign in cancelled"
            case .noToken: return "No access token returned"
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
