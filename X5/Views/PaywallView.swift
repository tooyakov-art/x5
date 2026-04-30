import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var sub: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var auth: Auth
    @StateObject private var iap = IAPService()
    @Environment(\.dismiss) private var dismiss

    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text("X5 Pro")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Text("Unlock everything for marketers and creators.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    Feature(text: "1000 credits added on subscribe")
                    Feature(text: "All AI tools (image, video, lipsync, design)")
                    Feature(text: "Full courses library")
                    Feature(text: "Hire vetted marketers in Hub")
                    Feature(text: "Priority support")
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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
                            Text("Cancel anytime in iOS Settings")
                                .font(.system(size: 12))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(iap.product != nil && !iap.isPurchasing ? Color.accentColor : Color.accentColor.opacity(0.5))
                        .cornerRadius(16)
                    }
                    .disabled(iap.product == nil || iap.isPurchasing)

                    Button("Restore purchases") {
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

                HStack(spacing: 18) {
                    Link("Terms", destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    Link("Privacy", destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
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
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
        }
        .task { await iap.loadProducts() }
        .alert("Welcome to Pro!", isPresented: $showSuccess) {
            Button("Continue") { dismiss() }
        } message: {
            Text("1000 credits have been added to your balance.")
        }
    }

    private var buttonTitle: String {
        if iap.isPurchasing { return "Processing…" }
        if let p = iap.product {
            return "Subscribe — \(p.displayPrice) / month"
        }
        return "Subscribe — $9.99 / month"
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
