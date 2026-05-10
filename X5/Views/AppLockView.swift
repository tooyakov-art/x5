import SwiftUI
import LocalAuthentication

/// Full-screen biometric lock shown over the app when `x5.face_id_enabled` is true.
/// Triggered on every cold launch and on resume from background.
struct AppLockView: View {
    @Binding var isLocked: Bool
    private let loc = LocalizationService.shared
    @State private var failureMessage: String?
    @State private var attempting = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Text("X5")
                    .font(.system(size: 56, weight: .black))
                    .italic()
                    .foregroundColor(.white)
                    .kerning(-2)
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 24)

                Image(systemName: "faceid")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.accentColor)

                Text(loc.t("app_lock_unlock_title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                if let m = failureMessage {
                    Text(m)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer()

                Button {
                    authenticate()
                } label: {
                    HStack(spacing: 8) {
                        if attempting { ProgressView().tint(.black) }
                        Image(systemName: "faceid")
                        Text(attempting ? loc.t("app_lock_checking") : loc.t("app_lock_button"))
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 28)
                .disabled(attempting)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { authenticate() }
    }

    private func authenticate() {
        guard !attempting else { return }
        attempting = true
        failureMessage = nil
        let context = LAContext()
        context.localizedFallbackTitle = loc.t("app_lock_passcode_fallback")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            attempting = false
            failureMessage = loc.t("app_lock_unavailable")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: loc.t("app_lock_reason")) { ok, err in
            DispatchQueue.main.async {
                attempting = false
                if ok {
                    withAnimation(.easeInOut(duration: 0.2)) { isLocked = false }
                } else {
                    failureMessage = (err as NSError?)?.localizedDescription ?? loc.t("app_lock_failed")
                }
            }
        }
    }
}
