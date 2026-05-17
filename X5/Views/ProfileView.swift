import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var iap = IAPService()
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton: Bool = true

    @State private var showingPaywall = false
    @State private var showingVerified = false
    @State private var showingSettings = false
    @State private var showingEdit = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var avatarError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero

                    VStack(spacing: 16) {
                        if currentUser.profile?.isPro == true {
                            proHero
                        } else {
                            upgradeCard
                        }
                        if let bio = currentUser.profile?.bio, !bio.isEmpty {
                            BioCard(text: bio)
                        }
                        if currentUser.profile?.showInHub != true {
                            becomeSpecialistCard
                        }
                        if let uid = currentUser.profile?.id {
                            PortfolioGrid(userId: uid, canEdit: true)
                        }
                        socialLinks
                        if let cats = currentUser.profile?.specialistCategory, !cats.isEmpty {
                            specialistCard(cats: cats)
                        }
                        if !(currentUser.profile?.hasActiveVerifiedBadge ?? false) {
                            verifiedCard
                        }
                    }
                    .frame(maxWidth: profileContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "profileScroll")
            .scrollIndicators(.hidden)
            .refreshable { await refreshProfile() }
            .background { X5Background() }
            .ignoresSafeArea(edges: .top)
            .navigationTitle(loc.t("profile_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsDoneButton {
                        Button(loc.t("btn_done")) { dismiss() }
                    } else {
                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            Image(systemName: uploadingAvatar ? "hourglass" : "camera.fill")
                        }
                        .disabled(uploadingAvatar)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingVerified) { VerifiedBadgeView() }
            .sheet(isPresented: $showingEdit) { EditProfileView() }
            .alert("Фото не сохранилось", isPresented: Binding(
                get: { avatarError != nil },
                set: { if !$0 { avatarError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(avatarError ?? "")
            }
            .onChange(of: avatarPickerItem) { newItem in
                guard let item = newItem else { return }
                Task { await uploadAvatar(item) }
            }
            .task { await iap.loadProducts() }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        GeometryReader { proxy in
            let pull = max(proxy.frame(in: .named("profileScroll")).minY, 0)
            let height = heroHeight + pull

            ZStack(alignment: .bottom) {
                ProfileCoverPhoto(urlString: currentUser.profile?.avatar,
                                  name: displayName)
                    .frame(width: proxy.size.width, height: height)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.clear,
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: proxy.size.width, height: height)
                .allowsHitTesting(false)

                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 42, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
                        if currentUser.profile?.hasActiveVerifiedBadge == true {
                            VerifiedChip(size: 18)
                        }
                    }
                    if !handleText.isEmpty {
                        Text(handleText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.66))
                    }

                    Button {
                        showingEdit = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                            Text("Edit profile")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.black)

                    HStack(spacing: 6) {
                        Text(planLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(currentUser.profile?.isPro == true ? .black : .white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(currentUser.profile?.isPro == true ? Color.accentColor : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        if let n = currentUser.profile?.signupNumber {
                            Text("#\(n)")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }

                    heroStatsRow
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: profileContentWidth)
                .frame(maxWidth: .infinity)
            }
            .frame(width: proxy.size.width, height: height)
            .offset(y: -pull)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let token = await auth.freshAccessToken() else {
            avatarError = "Сессия устарела. Войди заново и попробуй еще раз."
            avatarPickerItem = nil
            return
        }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.85) {
            let url = await currentUser.uploadAvatar(jpeg, accessToken: token)
            if url == nil {
                avatarError = "Сервер не принял фото. Проверь доступ к аккаунту и попробуй еще раз."
            }
        } else {
            avatarError = "Не удалось прочитать фото."
        }
        avatarPickerItem = nil
    }

    // MARK: - Stats

    private var heroStatsRow: some View {
        HStack(spacing: 8) {
            StatBubble(value: "\(currentUser.profile?.credits ?? 0)", label: "Credits")
            StatBubble(value: "0", label: "Followers")
            StatBubble(value: "0", label: "Following")
        }
    }

    private var heroHeight: CGFloat {
        max(UIScreen.main.bounds.height * 0.78, 640)
    }

    private var profileContentWidth: CGFloat {
        min(UIScreen.main.bounds.width - 32, 390)
    }

    private func refreshProfile() async {
        guard let uid = auth.userId, let token = await auth.freshAccessToken() else { return }
        await currentUser.load(userId: uid, accessToken: token)
        subscription.sync(from: currentUser.profile)
        await iap.loadProducts()
    }

    private var displayName: String {
        let raw = currentUser.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, raw != "User", raw != "X5" { return raw }
        if let emailName = emailPrefix { return emailName }
        return "X5"
    }

    private var handleText: String {
        if let nick = currentUser.profile?.nickname, !nick.isEmpty { return "@\(nick)" }
        if let emailName = emailPrefix { return "@\(emailName.lowercased())" }
        return ""
    }

    private var emailPrefix: String? {
        guard let email = auth.userEmail, let prefix = email.split(separator: "@").first else { return nil }
        let cleaned = String(prefix).replacingOccurrences(of: ".", with: " ")
        return cleaned.isEmpty ? nil : cleaned.capitalized
    }

    // MARK: - Pro hero / upgrade card

    private var proHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.accentColor)
                Text("X5 Pro В· active")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Manage") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
            }
            if let end = currentUser.profile?.subscriptionEndDate {
                Text("Renews \(formatDate(end))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(14)
        .x5ClearGlass(cornerRadius: 16, highlight: 0.12)
    }

    private var upgradeCard: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Upgrade to Pro").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(upgradeSubtitle).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .x5ClearGlass(cornerRadius: 16, highlight: 0.12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Become a specialist

    private var becomeSpecialistCard: some View {
        Button {
            showingEdit = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("РЎС‚Р°С‚СЊ СЃРїРµС†РёР°Р»РёСЃС‚РѕРј")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Р’РєР»СЋС‡Рё РїСѓР±Р»РёС‡РЅС‹Р№ РїСЂРѕС„РёР»СЊ вЂ” РєР»РёРµРЅС‚С‹ РЅР°Р№РґСѓС‚ С‚РµР±СЏ РІ Hub Рё РЅР°РїРёС€СѓС‚ РІ С‡Р°С‚")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .x5ClearGlass(cornerRadius: 16, highlight: 0.12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verified upsell

    private var verifiedCard: some View {
        Button {
            showingVerified = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color.accentColor, .blue],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("РџРѕР»СѓС‡РёС‚СЊ РіР°Р»РѕС‡РєСѓ").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text("РЎРёРЅСЏСЏ в‘ СЂСЏРґРѕРј СЃ РёРјРµРЅРµРј вЂ” Р±РѕР»СЊС€Рµ РґРѕРІРµСЂРёСЏ Рё РїСЂРёРѕСЂРёС‚РµС‚ РІ Hub")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .x5ClearGlass(cornerRadius: 16, highlight: 0.12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Social

    @ViewBuilder
    private var socialLinks: some View {
        if let links = currentUser.profile?.socialLinks {
            VStack(alignment: .leading, spacing: 10) {
                Text("SOCIAL")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.45))
                HStack(spacing: 8) {
                    if let v = links.telegram, !v.isEmpty {
                        SocialChip(label: "Telegram", value: v, systemImage: "paperplane.fill") { open(telegram: v) }
                    }
                    if let v = links.whatsapp, !v.isEmpty {
                        SocialChip(label: "WhatsApp", value: v, systemImage: "phone.fill") { open(whatsapp: v) }
                    }
                    if let v = links.instagram, !v.isEmpty {
                        SocialChip(label: "Instagram", value: v, systemImage: "camera.fill") { open(instagram: v) }
                    }
                }
            }
        }
    }

    private func specialistCard(cats: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SPECIALIST")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(currentUser.profile?.showInHub == true ? "On Hub" : "Hidden")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(currentUser.profile?.showInHub == true ? .accentColor : .white.opacity(0.5))
            }
            HStack(spacing: 6) {
                ForEach(cats.prefix(3), id: \.self) { id in
                    Text(HubCategories.label(for: id))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .x5ClearGlass(cornerRadius: 14, highlight: 0.10)
    }

    // MARK: - Helpers

    private var planLabel: String {
        currentUser.profile?.planLabel.uppercased() ?? "FREE"
    }

    /// Real subscription price from StoreKit / ASC. Loaded once on appear.
    private var upgradeSubtitle: String {
        if let p = iap.product {
            return "\(p.displayPrice) / month вЂ” 1000 credits + all tools"
        }
        return "1000 credits + all tools"
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }

    private func open(telegram raw: String) {
        let user = raw.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: raw.hasPrefix("http") ? raw : "https://t.me/\(user)") {
            UIApplication.shared.open(url)
        }
    }
    private func open(whatsapp raw: String) {
        if raw.hasPrefix("http"), let url = URL(string: raw) { UIApplication.shared.open(url); return }
        let digits = raw.filter("0123456789".contains)
        if let url = URL(string: "https://wa.me/\(digits)") { UIApplication.shared.open(url) }
    }
    private func open(instagram raw: String) {
        let user = raw.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: raw.hasPrefix("http") ? raw : "https://instagram.com/\(user)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Components

private struct StatBubble: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .x5ClearGlass(cornerRadius: 14, highlight: 0.10)
    }
}

private struct BioCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .x5ClearGlass(cornerRadius: 14, highlight: 0.10)
    }
}

private struct SocialChip: View {
    let label: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .x5ClearGlass(cornerRadius: 18, highlight: 0.10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile cover helpers

private struct ProfileCoverPhoto: View {
    let urlString: String?
    let name: String?

    var body: some View {
        Group {
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.20, green: 0.45, blue: 0.85),
                Color(red: 0.05, green: 0.12, blue: 0.40)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: 80, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var initials: String {
        let parts = (name ?? "?").split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

private struct ProfileStatCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 28)
    }
}
