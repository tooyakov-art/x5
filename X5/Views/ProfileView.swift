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
    @State private var uploadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: 22) {
                    statsRow
                    if currentUser.profile?.isPro == true {
                        proHero
                    } else {
                        upgradeCard
                    }
                    if let bio = currentUser.profile?.bio, !bio.isEmpty {
                        BioCard(text: bio)
                    }
                    // CTA: become a specialist if not yet on Hub
                    if currentUser.profile?.showInHub != true {
                        becomeSpecialistCard
                    }
                    // Portfolio goes BEFORE verified card so the "+ Добавить" button is reachable
                    if let uid = currentUser.profile?.id {
                        PortfolioGrid(userId: uid, canEdit: true)
                    }
                    socialLinks
                    if let cats = currentUser.profile?.specialistCategory, !cats.isEmpty {
                        specialistCard(cats: cats)
                    }
                    // Verified upsell at the bottom — non-blocking
                    if !(currentUser.profile?.hasActiveVerifiedBadge ?? false) {
                        verifiedCard
                    }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(ProfileAmbientBackground().ignoresSafeArea())
            .navigationTitle(loc.t("profile_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Settings")
                }
                if showsDoneButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(loc.t("btn_done")) { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingVerified) { VerifiedBadgeView() }
            .sheet(isPresented: $showingEdit) { EditProfileView() }
            .alert("Фото не сохранилось", isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadError ?? "")
            }
            .task { await iap.loadProducts() }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            ProfilePortrait(urlString: currentUser.profile?.avatar,
                            name: currentUser.profile?.name ?? auth.userEmail)

            LinearGradient(colors: [
                .clear,
                Color.black.opacity(0.18),
                Color.black.opacity(0.82)
            ], startPoint: .center, endPoint: .bottom)

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    HStack(spacing: 7) {
                        Text(currentUser.profile?.displayName ?? auth.userEmail ?? "User")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if currentUser.profile?.hasActiveVerifiedBadge == true {
                            VerifiedChip(size: 19)
                        }
                    }
                    if let nick = currentUser.profile?.nickname, !nick.isEmpty {
                        Text("@\(nick)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.66))
                    }
                }

                Button {
                    showingEdit = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil")
                        Text("Edit profile")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .x5Glass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    HeroPill(text: planLabel, highlighted: currentUser.profile?.isPro == true)
                    if let n = currentUser.profile?.signupNumber {
                        HeroPill(text: "#\(n)", highlighted: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            if uploadingAvatar {
                Color.black.opacity(0.42)
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 46, height: 46)
                    .x5Glass(cornerRadius: 23)
                    }
                    .disabled(uploadingAvatar)
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(height: min(UIScreen.main.bounds.height * 0.72, 620))
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .onChange(of: avatarPickerItem) { newItem in
            guard let item = newItem else { return }
            Task { await uploadAvatar(item) }
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let token = auth.accessToken else {
            uploadError = "Сначала войди в аккаунт."
            return
        }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = resizedJPEG(image, maxSide: 1800, quality: 0.82) else {
            uploadError = "Не удалось прочитать выбранное фото."
            avatarPickerItem = nil
            return
        }
        let url = await currentUser.uploadAvatar(jpeg, accessToken: token)
        if url == nil {
            uploadError = currentUser.error ?? "Сервер не принял фото. Попробуй другое изображение."
        }
        avatarPickerItem = nil
    }

    private func resizedJPEG(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxSide / max(size.width, size.height), 1)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatBubble(value: "\(currentUser.profile?.credits ?? 0)", label: "Credits")
            StatBubble(value: "0", label: "Followers")
            StatBubble(value: "0", label: "Following")
        }
    }

    // MARK: - Pro hero / upgrade card

    private var proHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.accentColor)
                Text("X5 Pro · active")
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
        .profilePanel(cornerRadius: 18, accent: Color.accentColor.opacity(0.32))
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
            .profilePanel(cornerRadius: 18, accent: Color.accentColor.opacity(0.30))
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
                    Text("Стать специалистом")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Включи публичный профиль — клиенты найдут тебя в Hub и напишут в чат")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .profilePanel(cornerRadius: 18, accent: Color.accentColor.opacity(0.30))
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
                    Text("Получить галочку").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text("Синяя ☑ рядом с именем — больше доверия и приоритет в Hub")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .profilePanel(cornerRadius: 18, accent: Color.cyan.opacity(0.24))
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
        .profilePanel(cornerRadius: 18)
    }

    // MARK: - Helpers

    private var planLabel: String {
        currentUser.profile?.planLabel.uppercased() ?? "FREE"
    }

    /// Real subscription price from StoreKit / ASC. Loaded once on appear.
    private var upgradeSubtitle: String {
        if let p = iap.product {
            return "\(p.displayPrice) / month — 1000 credits + all tools"
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

struct ProfileAmbientBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.50, blue: 0.78).opacity(0.34),
                    Color.clear
                ],
                center: .init(x: 0.50, y: -0.08),
                startRadius: 20,
                endRadius: 430
            )
            RadialGradient(
                colors: [
                    Color(red: 0.52, green: 0.72, blue: 0.95).opacity(0.12),
                    Color.clear
                ],
                center: .init(x: 0.12, y: 0.16),
                startRadius: 10,
                endRadius: 340
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct ProfilePortrait: View {
    let urlString: String?
    let name: String?

    var body: some View {
        ZStack {
            portrait
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.02)
                .blur(radius: 18)
                .opacity(0.54)

            portrait
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .saturation(1.05)
                .contrast(1.04)
        }
        .clipped()
    }

    @ViewBuilder
    private var portrait: some View {
        if let raw = urlString, !raw.isEmpty, let url = URL(string: raw) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.09, blue: 0.15),
                    Color(red: 0.05, green: 0.40, blue: 0.62),
                    Color(red: 0.86, green: 0.90, blue: 0.94).opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(profileInitials(name))
                .font(.system(size: 74, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

struct HeroPill: View {
    let text: String
    let highlighted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundColor(highlighted ? .black : .white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlighted ? Color.white : Color.white.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
}

struct ProfilePanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.035))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent, lineWidth: 1)
            }
    }
}

extension View {
    func profilePanel(cornerRadius: CGFloat, accent: Color = Color.white.opacity(0.10)) -> some View {
        modifier(ProfilePanelModifier(cornerRadius: cornerRadius, accent: accent))
    }
}

private func profileInitials(_ name: String?) -> String {
    let parts = (name ?? "?").split(separator: " ")
    let first = parts.first?.first.map(String.init) ?? "?"
    let last = parts.dropFirst().first?.first.map(String.init) ?? ""
    return (first + last).uppercased()
}

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
        .profilePanel(cornerRadius: 18)
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
            .profilePanel(cornerRadius: 18)
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
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
