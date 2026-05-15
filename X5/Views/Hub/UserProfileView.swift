import SwiftUI

/// Public profile of another user (tapped from Hub).
/// Loads full profiles row + portfolio_items.
struct UserProfileView: View {
    let userId: String
    /// Optional already-fetched specialist row to render instantly.
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

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if !isMe {
                    sendMessageButton
                }
                if let bio = profile?.bio ?? fallback?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .profilePanel(cornerRadius: 18)
                }
                categoryChips
                socialButtons
                PortfolioGrid(userId: userId, canEdit: false)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(ProfileAmbientBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white.opacity(0.7))
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

    private var isMe: Bool { auth.userId == userId }

    private var sendMessageButton: some View {
        Button(action: openChat) {
            HStack(spacing: 8) {
                if openingChat {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                }
                Text(openingChat ? loc.t("user_open") : loc.t("user_send_message"))
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .white.opacity(0.14), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(openingChat || auth.accessToken == nil)
    }

    private func openChat() {
        guard let me = auth.userId, let token = auth.accessToken else { return }
        openingChat = true
        Task {
            let chat = await chats.ensureChat(otherUserId: userId, currentUserId: me, taskId: nil, taskTitle: nil, accessToken: token)
            openingChat = false
            if let chat { navigatingChat = chat }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            ProfilePortrait(urlString: profile?.avatar ?? fallback?.avatar,
                            name: profile?.name ?? fallback?.name)

            LinearGradient(colors: [
                .clear,
                Color.black.opacity(0.18),
                Color.black.opacity(0.84)
            ], startPoint: .center, endPoint: .bottom)

            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Text(profile?.name ?? fallback?.name ?? fallback?.nickname ?? "User")
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if (profile?.hasActiveVerifiedBadge ?? (fallback?.isVerified == true)) {
                        VerifiedChip(size: 19)
                    }
                }
                if let nick = profile?.nickname ?? fallback?.nickname, !nick.isEmpty {
                    Text("@\(nick)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.66))
                }
                if (profile?.plan ?? fallback?.plan) == "pro" {
                    HeroPill(text: "PRO", highlighted: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .frame(height: 430)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.cyan.opacity(0.14), radius: 30, x: 0, y: 18)
    }

    @ViewBuilder
    private var categoryChips: some View {
        let cats = profile?.specialistCategory ?? fallback?.specialistCategory ?? []
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
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
            }
            .padding(14)
            .profilePanel(cornerRadius: 18)
        }
    }

    @ViewBuilder
    private var socialButtons: some View {
        let links = profile?.socialLinks ?? fallback?.socialLinks
        if let links {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTACT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
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
                }
            }
            .padding(14)
            .profilePanel(cornerRadius: 18)
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
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

/// Simple flow layout for chip wrap.
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
