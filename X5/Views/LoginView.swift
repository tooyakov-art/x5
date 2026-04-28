import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: Auth
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 88, height: 88)
                    Text("X5")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.black)
                }

                Text("X5")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("AI caption writer for marketers.\nGenerate post copy in seconds.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Link("Privacy Policy", destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            do {
                try await auth.signInWithApple(authorization: authorization)
            } catch {
                errorMessage = "Sign-in failed. Please try again."
            }
        case .failure(let error as NSError):
            if error.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Sign-in failed. Please try again."
            }
        }
    }
}
