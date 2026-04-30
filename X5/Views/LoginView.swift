import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: Auth
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            X5Background()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    // Big italic X5 logo
                    Text("X5")
                        .font(.system(size: 84, weight: .black, design: .default))
                        .italic()
                        .foregroundColor(.white)
                        .kerning(-3)
                        .shadow(color: Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.6), radius: 32, x: 0, y: 0)

                    // Welcome title
                    Text("Welcome to X5")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    // Subtitle
                    Text("Marketing studio for creators.\nGenerate, learn, and hire — in one app.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 18) {
                        Link("Privacy Policy",
                             destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                        Text("·")
                        Link("Terms",
                             destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            do {
                try await auth.signInWithApple(authorization: authorization)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error as NSError):
            if error.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Apple: \(error.localizedDescription)"
            }
        }
    }
}
