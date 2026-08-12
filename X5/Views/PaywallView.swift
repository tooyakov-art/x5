import StoreKit
import SwiftUI

/// One-time credit store. The historical name is kept so existing callers do
/// not need to change while legacy subscriptions remain restorable elsewhere.
struct PaywallView: View {
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @EnvironmentObject private var iap: IAPService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var didLoadProducts = false
    @State private var purchasingProductID: String?
    @State private var kaspiPurchasingProductID: String?
    @State private var kaspiPayment: KaspiCreditPayment?
    @State private var kaspiError: String?
    @State private var purchasedCredits = 0
    @State private var profileReloadSucceeded = true
    @State private var showSuccess = false
    @AppStorage("x5.kaspi.pendingPaymentID")
    private var pendingKaspiPaymentID = ""

    private let kaspiService = KaspiCreditPaymentService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)

                    Text(loc.t("credit_store_title"))
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    Text(loc.t("credit_store_description"))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    balanceCard

                    VStack(spacing: 12) {
                        ForEach(IAPProductCatalog.visibleCreditPacks) { pack in
                            packCard(pack)
                        }
                    }

                    Text(loc.t("credit_store_delivery_note"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 18) {
                        if let termsURL = URL(string: "https://tooyakov-art.github.io/x5site/terms.html") {
                            Link(loc.t("credit_store_terms_link"), destination: termsURL)
                        }
                        if let privacyURL = URL(string: "https://tooyakov-art.github.io/x5site/privacy.html") {
                            Link(loc.t("credit_store_privacy_link"), destination: privacyURL)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)

                    if let error = iap.lastError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    if let kaspiError {
                        Text(kaspiError)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    if didLoadProducts && (hasMissingCreditPacks || iap.lastError != nil) {
                        Button {
                            Task { await reloadProducts() }
                        } label: {
                            Group {
                                if iap.isLoadingProducts {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(loc.t("btn_retry"))
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .foregroundStyle(.black)
                        .disabled(iap.isLoadingProducts || iap.isPurchasing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle(loc.t("credit_store_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("btn_done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await reloadProducts()
            await restorePendingKaspiPayment()
        }
        .task(id: kaspiPayment?.id) {
            await pollKaspiPaymentUntilFinished()
        }
        .alert(loc.t("credit_store_success_title"), isPresented: $showSuccess) {
            Button(loc.t("btn_done")) { dismiss() }
        } message: {
            let messageKey = IAPCreditPurchaseConfirmation.messageKey(
                profileReloadSucceeded: profileReloadSucceeded
            )
            if profileReloadSucceeded {
                Text(String(format: loc.t(messageKey), purchasedCredits))
            } else {
                Text(loc.t(messageKey))
            }
        }
    }

    private var balanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("credit_store_balance"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                Text((currentUser.profile?.credits ?? 0).formatted())
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(16)
        .x5ClearGlass(cornerRadius: 18, highlight: 0.12)
    }

    private func packCard(_ pack: IAPCreditPack) -> some View {
        let product = iap.product(id: pack.productID)
        let isCurrentPurchase = purchasingProductID == pack.productID && iap.isPurchasing
        let isCurrentKaspiPurchase = kaspiPurchasingProductID == pack.productID

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: loc.t("credit_store_pack_credits"), pack.credits))
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundColor(.white)
                    Text(loc.t("credit_store_one_time"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Text(product?.displayPrice ?? pack.fallbackDisplayPrice)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.accentColor)
            }

            Button {
                buy(pack)
            } label: {
                Group {
                    if isCurrentPurchase {
                        ProgressView().tint(.black)
                    } else {
                        Text(loc.t("credit_store_buy"))
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .foregroundStyle(.black)
            .disabled(product == nil || iap.isPurchasing)

            if KaspiInternalBetaAccess.isAllowed(userID: auth.userId),
               let amountKzt = KaspiCreditCatalog.priceKzt(for: pack.productID) {
                Button {
                    buyWithKaspi(pack)
                } label: {
                    Group {
                        if isCurrentKaspiPurchase {
                            ProgressView().tint(.white)
                        } else {
                            Text(
                                String(
                                    format: loc.t("credit_store_kaspi_buy"),
                                    amountKzt.formatted()
                                )
                            )
                            .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 24)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.86, green: 0.12, blue: 0.18))
                .foregroundStyle(.white)
                .disabled(
                    kaspiPurchasingProductID != nil || iap.isPurchasing
                )

                Text(loc.t("credit_store_kaspi_exact_amount"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if didLoadProducts && product == nil {
                Text(loc.t("credit_store_unavailable"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func buy(_ pack: IAPCreditPack) {
        purchasingProductID = pack.productID
        Task {
            defer { purchasingProductID = nil }
            let delivered = await iap.purchase(productID: pack.productID)
            guard delivered else {
                X5Feedback.error()
                return
            }

            profileReloadSucceeded = await refreshProfile()
            purchasedCredits = pack.credits
            X5Feedback.success()
            showSuccess = true
        }
    }

    private func buyWithKaspi(_ pack: IAPCreditPack) {
        guard kaspiPurchasingProductID == nil else { return }
        kaspiPurchasingProductID = pack.productID
        kaspiError = nil

        Task {
            defer { kaspiPurchasingProductID = nil }
            guard let accessToken = await auth.freshAccessToken() else {
                kaspiError = loc.t("credit_store_kaspi_sign_in")
                X5Feedback.error()
                return
            }

            do {
                let payment = try await kaspiService.create(
                    storeProductID: pack.productID,
                    accessToken: accessToken
                )
                kaspiPayment = payment
                pendingKaspiPaymentID = payment.id.uuidString.lowercased()
                DiagnosticLogger.log(event: "kaspi_payment_opened", extra: [
                    "payment": payment.id.uuidString.lowercased(),
                    "product": payment.productId
                ])
                _ = openURL(payment.paymentUrl)
            } catch let error as KaspiCreditPaymentError {
                kaspiError = error == .notConfigured
                    ? loc.t("credit_store_kaspi_not_configured")
                    : (error.errorDescription ?? loc.t("credit_store_kaspi_failed"))
                X5Feedback.error()
            } catch {
                kaspiError = loc.t("credit_store_kaspi_failed")
                X5Feedback.error()
            }
        }
    }

    private func restorePendingKaspiPayment() async {
        guard KaspiInternalBetaAccess.isAllowed(userID: auth.userId),
              kaspiPayment == nil,
              let paymentID = UUID(uuidString: pendingKaspiPaymentID),
              let accessToken = await auth.freshAccessToken()
        else { return }

        do {
            let payment = try await kaspiService.get(
                paymentID: paymentID,
                accessToken: accessToken
            )
            kaspiPayment = payment
            if payment.status != .pending {
                pendingKaspiPaymentID = ""
            }
        } catch {
            // Keep a recoverable pending order across temporary network errors.
        }
    }

    private func pollKaspiPaymentUntilFinished() async {
        guard var payment = kaspiPayment,
              payment.status == .pending
        else { return }

        while !Task.isCancelled && payment.status == .pending {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let accessToken = await auth.freshAccessToken() else {
                continue
            }
            do {
                payment = try await kaspiService.get(
                    paymentID: payment.id,
                    accessToken: accessToken
                )
                kaspiPayment = payment
            } catch {
                continue
            }
        }

        guard payment.status == .confirmed else {
            if payment.status != .pending {
                pendingKaspiPaymentID = ""
                kaspiError = loc.t("credit_store_kaspi_not_completed")
            }
            return
        }

        pendingKaspiPaymentID = ""
        profileReloadSucceeded = await refreshProfile()
        purchasedCredits = payment.credits
        X5Feedback.success()
        showSuccess = true
    }

    private var hasMissingCreditPacks: Bool {
        !IAPProductAvailability.missingCreditPackIDs(
            loadedProductIDs: iap.products.keys
        ).isEmpty
    }

    private func reloadProducts() async {
        didLoadProducts = false
        await iap.loadProducts()
        didLoadProducts = true
    }

    private func refreshProfile() async -> Bool {
        guard let userID = auth.userId,
              let accessToken = await auth.freshAccessToken() else {
            return false
        }
        return await currentUser.load(userId: userID, accessToken: accessToken)
    }
}
