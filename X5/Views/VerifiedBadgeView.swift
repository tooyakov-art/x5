import SwiftUI

/// Sells the blue ☑ verified badge for `IAPService.verifiedCostCredits` credits / 30 days.
/// Credits come from the Pro subscription (1000/mo) — single store, no separate IAP.
struct VerifiedBadgeView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var iap = IAPService()
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false
    @State private var showPaywall = false
    @State private var working = false
    @State private var errorText: String?

    private var credits: Int { currentUser.profile?.credits ?? 0 }
    private var canAfford: Bool { credits >= IAPService.verifiedCostCredits }

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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Готово!", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Синяя галочка теперь рядом с твоим именем. Списано \(IAPService.verifiedCostCredits) кредитов.")
        }
    }

    private var purchaseBlock: some View {
        VStack(spacing: 10) {
            // Cost block
            HStack(spacing: 8) {
                Image(systemName: "creditcard.circle.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(IAPService.verifiedCostCredits) кредитов / 30 дней")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Твой баланс: \(credits)")
                        .font(.system(size: 12))
                        .foregroundColor(canAfford ? .white.opacity(0.7) : .red.opacity(0.85))
                }
                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if canAfford {
                Button {
                    activate()
                } label: {
                    Text(working ? "Списываем…" : "Активировать за \(IAPService.verifiedCostCredits) кредитов")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(working ? Color.accentColor.opacity(0.5) : Color.accentColor)
                        .cornerRadius(14)
                }
                .disabled(working)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    VStack(spacing: 4) {
                        Text("Купить Pro и получить кредиты")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                        Text("Pro = +1000 кредитов сразу")
                            .font(.system(size: 11))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .cornerRadius(14)
                }
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

    private func activate() {
        guard let token = auth.accessToken else { return }
        working = true
        errorText = nil
        Task {
            let ok = await iap.activateVerifiedWithCredits(currentUser: currentUser, accessToken: token)
            working = false
            if ok {
                showSuccess = true
            } else {
                errorText = iap.lastError ?? "Не удалось активировать. Попробуй позже."
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
