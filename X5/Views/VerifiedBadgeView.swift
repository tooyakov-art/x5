import SwiftUI
import StoreKit

/// Sells the blue ☑ verified badge as a separate App Store subscription.
struct VerifiedBadgeView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @EnvironmentObject private var iap: IAPService
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                    if let termsURL = URL(string: "https://tooyakov-art.github.io/x5site/terms.html") {
                        Link("Terms", destination: termsURL)
                    }
                    if let privacyURL = URL(string: "https://tooyakov-art.github.io/x5site/privacy.html") {
                        Link("Privacy", destination: privacyURL)
                    }
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
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(IAPService.verifiedDisplayPrice) / месяц")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Отдельная покупка через App Store")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                buyVerified()
            } label: {
                VStack(spacing: 4) {
                    Text(iap.isPurchasing ? "Открываем App Store…" : "Купить галочку — \(IAPService.verifiedDisplayPrice) / мес")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text("Отменить можно в настройках Apple ID")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(verifiedProduct != nil && !iap.isPurchasing ? Color.accentColor : Color.accentColor.opacity(0.5))
                .cornerRadius(14)
            }
            .disabled(verifiedProduct == nil || iap.isPurchasing)

            if verifiedProduct == nil && iap.lastError == nil {
                Text("Покупка галочки сейчас недоступна. Проверь продукт в App Store Connect.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            if let err = errorText {
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

    private var verifiedProduct: Product? {
        iap.product(id: IAPService.verifiedMonthlyProductID)
    }

    private func buyVerified() {
        errorText = nil
        Task {
            let ok = await iap.purchase(productID: IAPService.verifiedMonthlyProductID)
            if ok {
                if let uid = auth.userId, let token = await auth.freshAccessToken() {
                    await currentUser.load(userId: uid, accessToken: token)
                }
                showSuccess = true
            } else {
                errorText = iap.lastError ?? "Не удалось купить галочку. Попробуй позже."
            }
        }
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
