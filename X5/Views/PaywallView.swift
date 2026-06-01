import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var sub: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var iap = IAPService()
    @Environment(\.dismiss) private var dismiss

    @State private var showSuccess = false
    @State private var selectedPlan: PaywallPlan = .pro

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .light))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                Text(loc.t("paywall_title"))
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Text(loc.t("paywall_desc"))
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Выбери тариф")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)

                    HStack(spacing: 10) {
                        ForEach(PaywallPlan.allCases) { plan in
                            PlanCard(plan: plan, isSelected: selectedPlan == plan) {
                                selectedPlan = plan
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Что входит")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)

                    Feature(text: selectedPlan.creditsText)
                    Feature(text: loc.t("paywall_feat_tools"))
                    Feature(text: loc.t("paywall_feat_courses"))
                    Feature(text: loc.t("paywall_feat_hub"))
                    Feature(text: loc.t("paywall_feat_support"))
                }
                .padding(18)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VerifiedAddonCard()

                VStack(spacing: 10) {
                    Button {
                        Task {
                            let ok = await iap.purchase(productID: selectedPlan.productID)
                            if ok {
                                if let uid = auth.userId, let token = auth.accessToken {
                                    await currentUser.load(userId: uid, accessToken: token)
                                }
                                showSuccess = true
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(buttonTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.black)
                            if selectedProduct != nil {
                                Text(loc.t("paywall_cancel_anytime"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedProduct != nil && !iap.isPurchasing ? Color.accentColor : Color.accentColor.opacity(0.5))
                        .cornerRadius(16)
                    }
                    .disabled(selectedProduct == nil || iap.isPurchasing)

                    if selectedProduct == nil && iap.lastError == nil {
                        Text(loc.t("paywall_unavailable"))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }

                    Button(loc.t("paywall_restore")) {
                        Task {
                            await iap.restore()
                            if let uid = auth.userId, let token = auth.accessToken {
                                await currentUser.load(userId: uid, accessToken: token)
                            }
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))

                    if let err = iap.lastError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }

                Text(loc.t("paywall_subscription_terms"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                HStack(spacing: 18) {
                    if let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        Link(loc.t("paywall_terms_link"), destination: eulaURL)
                    }
                    if let privacyURL = URL(string: "https://tooyakov-art.github.io/x5site/privacy.html") {
                        Link(loc.t("paywall_privacy_link"), destination: privacyURL)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
        }
        .task { await iap.loadProducts() }
        .alert(loc.t("paywall_welcome_pro"), isPresented: $showSuccess) {
            Button(loc.t("paywall_continue")) { dismiss() }
        } message: {
            Text(loc.t("paywall_credits_added"))
        }
    }

    private var buttonTitle: String {
        if iap.isPurchasing { return loc.t("btn_loading") }
        if let product = selectedProduct {
            return "\(loc.t("paywall_subscribe")) — \(product.displayPrice) / мес"
        }
        return loc.t("paywall_loading")
    }

    private var selectedProduct: Product? {
        iap.product(id: selectedPlan.productID)
    }
}

private enum PaywallPlan: String, CaseIterable, Identifiable {
    case lite
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lite: return "X5 Lite"
        case .pro: return "X5 Pro"
        }
    }

    var price: String {
        switch self {
        case .lite: return "1000 ₸"
        case .pro: return "2000 ₸"
        }
    }

    var productID: String {
        switch self {
        case .lite: return IAPService.liteMonthlyProductID
        case .pro: return IAPService.proMonthlyProductID
        }
    }

    var subtitle: String {
        switch self {
        case .lite: return "для старта"
        case .pro: return "лучший выбор"
        }
    }

    var creditsText: String {
        switch self {
        case .lite: return "500 кредитов каждый месяц"
        case .pro: return "2000 кредитов каждый месяц"
        }
    }

    var benefits: [String] {
        switch self {
        case .lite:
            return ["ИИ-картинки и тексты", "Базовые курсы", "Доступ к Hub"]
        case .pro:
            return ["Все AI-инструменты", "Премиум-курсы", "Приоритет в Hub"]
        }
    }
}

private struct PlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .heavy))
                        Text(plan.subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isSelected ? .black.opacity(0.58) : .white.opacity(0.45))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                }

                Text(plan.price)
                    .font(.system(size: 23, weight: .heavy))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.benefits, id: \.self) { benefit in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                            Text(benefit)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct VerifiedAddonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Синяя галочка")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)
                    Text("отдельно: 500 кредитов / 30 дней")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Feature(text: "Профиль выглядит проверенным")
                Feature(text: "Больше доверия в Hub и откликах")
                Feature(text: "Отдельно от подписки, включается когда нужно")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LinearGradient(colors: [.cyan.opacity(0.6), .blue.opacity(0.2)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing), lineWidth: 1)
        )
    }
}

private struct Feature: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}
