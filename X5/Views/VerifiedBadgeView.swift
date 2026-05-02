import SwiftUI
import StoreKit

/// Sells the blue ☑ verified badge as a 990 ₸/mo subscription
/// (StoreKit product: com.x5studio.app.verified.monthly).
struct VerifiedBadgeView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var iap = IAPService()
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor, .blue],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(.white)
                }
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)

                Text(loc.t("verified_title"))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Text(loc.t("verified_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    Benefit(icon: "arrow.up.circle.fill", text: loc.t("verified_benefit_1"))
                    Benefit(icon: "shield.checkered", text: loc.t("verified_benefit_2"))
                    Benefit(icon: "person.crop.circle.badge.checkmark", text: loc.t("verified_benefit_3"))
                }
                .padding(18)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if currentUser.profile?.hasActiveVerifiedBadge == true {
                    activeBlock
                } else {
                    purchaseBlock
                }

                HStack(spacing: 18) {
                    Link("Terms", destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    Link("Privacy", destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
        }
        .task { await iap.loadProducts() }
        .alert("Готово!", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Синяя галочка теперь рядом с твоим именем.")
        }
    }

    private var purchaseBlock: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    let ok = await iap.purchaseVerified()
                    if ok {
                        if let uid = auth.userId, let token = auth.accessToken {
                            await currentUser.load(userId: uid, accessToken: token)
                        }
                        showSuccess = true
                    }
                }
            } label: {
                Text(buttonLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(iap.verifiedProduct != nil && !iap.isPurchasing
                                ? Color.accentColor : Color.accentColor.opacity(0.5))
                    .cornerRadius(14)
            }
            .disabled(iap.verifiedProduct == nil || iap.isPurchasing)

            if iap.verifiedProduct == nil && iap.lastError == nil {
                Text(loc.t("paywall_unavailable"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            if let err = iap.lastError {
                Text(err).font(.system(size: 11)).foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var activeBlock: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            Text(loc.t("verified_active") + " " + formatDate(currentUser.profile?.verifiedUntil))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttonLabel: String {
        if iap.isPurchasing { return loc.t("btn_loading") }
        if let p = iap.verifiedProduct {
            return "\(loc.t("paywall_subscribe")) — \(p.displayPrice) / mo"
        }
        return loc.t("paywall_loading")
    }

    private func formatDate(_ iso: String?) -> String {
        guard let iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

private struct Benefit: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 0)
        }
    }
}

/// Small ☑ chip rendered next to a name when the user has an active verified subscription.
struct VerifiedChip: View {
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(.accentColor)
    }
}
