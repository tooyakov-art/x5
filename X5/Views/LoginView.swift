import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService

    @State private var mode: Mode = .select
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var loading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    enum Mode { case select, email }
    enum Field { case email, password }

    var body: some View {
        ZStack {
            X5Background()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                logoBlock
                    .padding(.bottom, 36)
                content
                Spacer(minLength: 0)
                legalBlock
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var logoBlock: some View {
        VStack(spacing: 14) {
            Text("X5")
                .font(.system(size: 84, weight: .black))
                .italic()
                .foregroundColor(.white)
                .kerning(-3)
                .shadow(color: Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.6), radius: 32, x: 0, y: 0)

            Text(mode == .email
                 ? (isSignUp ? loc.t("login_signup") : loc.t("login_signin"))
                 : loc.t("login_title"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if mode == .select {
                Text(loc.t("login_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .select: selectButtons
        case .email:  emailForm
        }
    }

    private var selectButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await handleGoogle() }
            } label: {
                HStack(spacing: 10) {
                    if loading {
                        ProgressView().tint(.black)
                    } else {
                        Text("G")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.black)
                    }
                    Text(loc.t("login_continue_google"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(loading)

            Button {
                mode = .email
                errorMessage = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                    Text(loc.t("login_continue_email"))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if let err = errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField(loc.t("login_email"), text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .focused($focused, equals: .email)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)

            SecureField(loc.t("login_password"), text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focused, equals: .password)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)

            Button(action: submit) {
                HStack {
                    if loading { ProgressView().tint(.black) }
                    Text(loading ? loc.t("btn_loading") : (isSignUp ? loc.t("login_create") : loc.t("login_signin")))
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmit || loading)
            .buttonStyle(.plain)

            Button {
                isSignUp.toggle()
                errorMessage = nil
            } label: {
                Text(isSignUp ? loc.t("login_have_account") : loc.t("login_new_here"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            if let err = errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            Button {
                mode = .select
                errorMessage = nil
                email = ""
                password = ""
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(loc.t("btn_back"))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
    }

    private var legalBlock: some View {
        HStack(spacing: 14) {
            Link("Privacy Policy",
                 destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
            Text("·")
            Link("Terms",
                 destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
        }
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.5))
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func submit() {
        guard canSubmit else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await auth.signUpWithEmail(email, password: password)
                } else {
                    try await auth.signInWithEmail(email, password: password)
                }
            } catch {
                errorMessage = humanError(error)
            }
            loading = false
        }
    }

    private func humanError(_ error: Error) -> String {
        let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if msg.localizedCaseInsensitiveContains("invalid login") { return "Invalid email or password." }
        if msg.localizedCaseInsensitiveContains("already registered") { return "This email is already registered." }
        if msg.localizedCaseInsensitiveContains("password should") { return "Password must be at least 6 characters." }
        return msg
    }

    private func handleGoogle() async {
        errorMessage = nil
        loading = true
        defer { loading = false }
        do {
            try await auth.signInWithGoogle()
        } catch {
            let msg = error.localizedDescription
            // Silent on cancel
            if msg.localizedCaseInsensitiveContains("cancel") { return }
            // Real error — show full text so user can debug (provider misconfig, redirect URL, etc.)
            errorMessage = "Google: \(msg)"
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            do {
                try await auth.signInWithApple(authorization: authorization)
            } catch {
                errorMessage = humanError(error)
            }
        case .failure(let error as NSError):
            if error.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Apple: \(error.localizedDescription)"
            }
        }
    }
}
