import SwiftUI

/// Public profile — Instagram-style layout с большой обложкой:
/// фото на полэкрана, имя, кнопка Follow, 3 колонки статистики и портфолио.
struct UserProfileView: View {
    let userId: String
    let fallback: HubSpecialist?

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chats = ChatsService()

    @State private var profile: UserProfile?
    @State private var isLoading: Bool = false
    @State private var openingChat: Bool = false
    @State private var navigatingChat: ChatRoom?
    @State private var confirmBlock = false
    @State private var portfolioCount: Int = 0

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                coverHeader
                actionRow
                statsRow
                bioBlock
                categoryChips
                socialButtons
                PortfolioGrid(userId: userId, canEdit: false)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                Spacer(minLength: 24)
            }
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if !isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            reportUser()
                        } label: {
                            Label(loc.t("hub_report_user"), systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            confirmBlock = true
                        } label: {
                            Label(loc.t("hub_block_user"), systemImage: "hand.raised.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                }
            }
        }
        .alert(loc.t("hub_block_user_title"), isPresented: $confirmBlock) {
            Button(loc.t("btn_cancel"), role: .cancel) {}
            Button(loc.t("hub_block_user"), role: .destructive) {
                BlockList.add(userId)
                dismiss()
            }
        } message: {
            Text(loc.t("hub_block_user_message"))
        }
        .task { await load() }
        .sheet(item: $navigatingChat) { chat in
            NavigationStack { ChatThreadView(chat: chat) }
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Большая обложка с фото и именем

    private var coverHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Фото на весь верх (фоном)
            CoverPhoto(urlString: profile?.avatar ?? fallback?.avatar,
                       name: profile?.name ?? fallback?.name)
                .frame(height: UIScreen.main.bounds.height * 1.0)
                .clipped()

            // Тёмный градиент вниз для читаемости текста
            LinearGradient(colors: [
                Color.clear,
                Color.black.opacity(0.20),
                Color.black.opacity(0.55),
                Color.black.opacity(0.90)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: UIScreen.main.bounds.height * 1.0)
            .allowsHitTesting(false)

            // Имя и nickname слева снизу
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    if (profile?.hasActiveVerifiedBadge ?? (fallback?.isVerified == true)) {
                        VerifiedChip(size: 18)
                    }
                    if (profile?.plan ?? fallback?.plan) == "pro" {
                        Text("PRO")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                if let nick = profile?.nickname ?? fallback?.nickname, !nick.isEmpty {
                    Text("@\(nick)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Кнопки Follow + message

    private var actionRow: some View {
        HStack(spacing: 10) {
            if isMe {
                Button {
                    NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
                } label: {
                    Text("Edit Profile")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: openChat) {
                    HStack(spacing: 8) {
                        if openingChat {
                            ProgressView().tint(.black)
                        }
                        Text(openingChat ? loc.t("user_open") : "Follow")
                    }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(openingChat || auth.accessToken == nil)

                Button(action: openChat) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(openingChat || auth.accessToken == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 3 колонки статистики

    private var statsRow: some View {
        HStack(spacing: 0) {
            StatCell(value: followingValue, label: "Following")
            StatDivider()
            StatCell(value: followersValue, label: "Followers")
            StatDivider()
            StatCell(value: creationsValue, label: "Creations")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(colors: [
                        Color.white.opacity(0.25),
                        Color.white.opacity(0.05)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private var followingValue: String { "—" }
    private var followersValue: String { "—" }
    private var creationsValue: String {
        portfolioCount > 0 ? "\(portfolioCount)" : "—"
    }

    private var bioBlock: some View {
        Group {
            if let bio = profile?.bio ?? fallback?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
            }
        }
    }

    @ViewBuilder
    private var categoryChips: some View {
        let cats = profile?.specialistCategory ?? fallback?.specialistCategory ?? []
        if !cats.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(cats, id: \.self) { id in
                    Text(HubCategories.label(for: id))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var socialButtons: some View {
        let links = profile?.socialLinks ?? fallback?.socialLinks
        if let links {
            HStack(spacing: 8) {
                if let v = links.telegram, !v.isEmpty {
                    SocialLink(systemImage: "paperplane.fill", url: makeTelegram(v))
                }
                if let v = links.whatsapp, !v.isEmpty {
                    SocialLink(systemImage: "phone.fill", url: makeWhatsApp(v))
                }
                if let v = links.instagram, !v.isEmpty {
                    SocialLink(systemImage: "camera.fill", url: makeInstagram(v))
                }
                if let v = links.youtube, !v.isEmpty, let u = URL(string: v) {
                    SocialLink(systemImage: "play.rectangle.fill", url: u)
                }
                if let v = links.tiktok, !v.isEmpty, let u = URL(string: v) {
                    SocialLink(systemImage: "music.note", url: u)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        profile?.displayName ?? fallback?.name ?? fallback?.nickname ?? "User"
    }

    private var isMe: Bool { auth.userId == userId }

    private func openChat() {
        guard let me = auth.userId, let token = auth.accessToken else { return }
        openingChat = true
        Task {
            let chat = await chats.ensureChat(otherUserId: userId, currentUserId: me, taskId: nil, taskTitle: nil, accessToken: token)
            openingChat = false
            if let chat { navigatingChat = chat }
        }
    }

    private func reportUser() {
        let subject = "Report user \(userId)"
        let body = "Hi X5 team,\n\nI'd like to report this user. Please review their content.\n\nUser ID: \(userId)\n"
        let to = "appreview@x5studio.app"
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(to)?subject=\(s)&body=\(b)") {
            UIApplication.shared.open(url)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let rows = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profile = rows.first
        }
        await loadPortfolioCount()
    }

    private func loadPortfolioCount() async {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "id")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        if let (data, response) = try? await URLSession.shared.data(for: request) {
            if let http = response as? HTTPURLResponse,
               let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.map(String.init),
               let n = Int(total) {
                portfolioCount = n
            } else if let rows = try? JSONDecoder().decode([[String: String]].self, from: data) {
                portfolioCount = rows.count
            }
        }
    }

    private func makeTelegram(_ raw: String) -> URL? {
        if raw.hasPrefix("http") { return URL(string: raw) }
        let user = raw.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://t.me/\(user)")
    }
    private func makeWhatsApp(_ raw: String) -> URL? {
        if raw.hasPrefix("http") { return URL(string: raw) }
        let digits = raw.filter("0123456789".contains)
        return URL(string: "https://wa.me/\(digits)")
    }
    private func makeInstagram(_ raw: String) -> URL? {
        if raw.hasPrefix("http") { return URL(string: raw) }
        let user = raw.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://instagram.com/\(user)")
    }
}

// MARK: - Subviews

private struct CoverPhoto: View {
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
                .font(.system(size: 80, weight: .heavy, design: .rounded))
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

private struct StatCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 28)
    }
}

private struct SocialLink: View {
    let systemImage: String
    let url: URL?

    var body: some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += lineH + spacing; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: sz.width, height: sz.height))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}