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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                planCard

                VStack(spacing: 10) {
                    Button {
                        Task {
                            let ok = await iap.purchaseMonthly()
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
                            if iap.product != nil {
                                Text(loc.t("paywall_cancel_anytime"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(iap.product != nil && !iap.isPurchasing ? Color.white : Color.white.opacity(0.45))
                        .cornerRadius(16)
                    }
                    .disabled(iap.product == nil || iap.isPurchasing)

                    if iap.product == nil && iap.lastError == nil {
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
            .padding(.top, 54)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(PaywallBackdrop())
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
        if let p = iap.product {
            return "\(loc.t("paywall_subscribe")) — \(p.displayPrice) / mo"
        }
        return loc.t("paywall_loading")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("X5")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .x5Glass(cornerRadius: 14)
                Spacer()
                Text("PRO")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.72))
            }

            Text("Pricing")
                .font(.system(size: 62, weight: .heavy))
                .foregroundColor(.white.opacity(0.11))
                .overlay(alignment: .bottomLeading) {
                    Text(loc.t("paywall_title"))
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                }

            Text(loc.t("paywall_desc"))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.68))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pro")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.82))
                Text(priceText)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)
                Text("For creators, marketers, and specialists working with clients.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                Feature(text: loc.t("paywall_feat_credits"))
                Feature(text: loc.t("paywall_feat_tools"))
                Feature(text: loc.t("paywall_feat_courses"))
                Feature(text: loc.t("paywall_feat_hub"))
                Feature(text: loc.t("paywall_feat_support"))
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [
                Color.white.opacity(0.18),
                Color.white.opacity(0.055),
                Color(red: 0.13, green: 0.39, blue: 0.48).opacity(0.18)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.28, green: 0.78, blue: 0.92).opacity(0.24), radius: 24, x: 0, y: 0)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var priceText: String {
        if let p = iap.product { return "\(p.displayPrice)/m" }
        return "$9.99/m"
    }
}

private struct Feature: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(3)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}

private struct PaywallBackdrop: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Text("Pricing")
                .font(.system(size: 112, weight: .heavy))
                .foregroundColor(.white.opacity(0.06))
                .scaleEffect(x: 1.08, y: 1)
                .offset(x: 36, y: -170)

            RadialGradient(colors: [
                Color(red: 0.18, green: 0.76, blue: 0.98).opacity(0.78),
                Color(red: 0.06, green: 0.12, blue: 0.50).opacity(0.36),
                Color.clear
            ], center: .topTrailing, startRadius: 20, endRadius: 360)
            .ignoresSafeArea()
            .blur(radius: 18)

            RadialGradient(colors: [
                Color.white.opacity(0.52),
                Color(red: 0.20, green: 0.74, blue: 0.90).opacity(0.35),
                Color.clear
            ], center: .bottomLeading, startRadius: 8, endRadius: 260)
            .ignoresSafeArea()
            .blur(radius: 28)

            VStack {
                Spacer()
                Ellipse()
                    .fill(
                        LinearGradient(colors: [
                            Color.white.opacity(0.68),
                            Color(red: 0.16, green: 0.66, blue: 0.90).opacity(0.42),
                            Color.clear
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 460, height: 150)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -92, y: -70)
                    .blur(radius: 10)
            }
            .ignoresSafeArea()
        }
    }
}
