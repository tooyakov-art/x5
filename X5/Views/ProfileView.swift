import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton: Bool = true

    @State private var showingPaywall = false
    @State private var showingVerified = false
    @State private var showingSettings = false
    @State private var showingEdit = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var uploadingAvatar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    statsRow
                    if currentUser.profile?.isPro == true {
                        proHero
                    } else {
                        upgradeCard
                    }
                    if let bio = currentUser.profile?.bio, !bio.isEmpty {
                        BioCard(text: bio)
                    }
                    if !(currentUser.profile?.hasActiveVerifiedBadge ?? false) {
                        verifiedCard
                    }
                    if let uid = currentUser.profile?.id {
                        PortfolioGrid(userId: uid, canEdit: true)
                    }
                    socialLinks
                    if let cats = currentUser.profile?.specialistCategory, !cats.isEmpty {
                        specialistCard(cats: cats)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Profile")
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
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingVerified) { VerifiedBadgeView() }
            .sheet(isPresented: $showingEdit) { EditProfileView() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(urlString: currentUser.profile?.avatar,
                           name: currentUser.profile?.name ?? auth.userEmail,
                           size: 96)
                if uploadingAvatar {
                    Circle().fill(Color.black.opacity(0.5)).frame(width: 96, height: 96)
                    ProgressView().tint(.white)
                }
                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(red: 0.04, green: 0.05, blue: 0.10), lineWidth: 3))
                }
                .disabled(uploadingAvatar)
            }
            .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(currentUser.profile?.displayName ?? auth.userEmail ?? "User")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                    if currentUser.profile?.hasActiveVerifiedBadge == true {
                        VerifiedChip(size: 18)
                    }
                }
                if let nick = currentUser.profile?.nickname, !nick.isEmpty {
                    Text("@\(nick)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
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
            }

            Button {
                showingEdit = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Edit profile")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .onChange(of: avatarPickerItem) { newItem in
            guard let item = newItem else { return }
            Task { await uploadAvatar(item) }
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let token = auth.accessToken else { return }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.85) {
            await currentUser.uploadAvatar(jpeg, accessToken: token)
        }
        avatarPickerItem = nil
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
        .background(Color.accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Text("$9.99 / month — 1000 credits + all tools").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private var planLabel: String {
        currentUser.profile?.planLabel.uppercased() ?? "FREE"
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
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
